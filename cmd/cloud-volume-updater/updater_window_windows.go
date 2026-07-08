//go:build windows

// Custom-painted Win32 progress window for the standalone updater.
//
// Replaces the previous MessageBox approach with a real window that matches
// the app's visual style: light background, dark text, Microsoft YaHei UI font,
// a step label, and a segmented progress bar. The update runs on a background
// goroutine while the main thread runs a standard Win32 message pump. When the
// update finishes (success or failure) the window is closed and the process
// exits. Every status change is mirrored to the diagnostic log file.
package main

import (
	"fmt"
	"os"
	"sync"
	"syscall"
	"time"
	"unsafe"
)

// Win32 DLLs and procs used by the windowed updater.
var (
	user32   = syscall.NewLazyDLL("user32.dll")
	kernel32 = syscall.NewLazyDLL("kernel32.dll")
	gdi32    = syscall.NewLazyDLL("gdi32.dll")
	dwmapi   = syscall.NewLazyDLL("dwmapi.dll")

	procGetModuleHandle = kernel32.NewProc("GetModuleHandleW")
	procRegisterClassEx = user32.NewProc("RegisterClassExW")
	procCreateWindowEx  = user32.NewProc("CreateWindowExW")
	procDefWindowProc   = user32.NewProc("DefWindowProcW")
	procGetMessage      = user32.NewProc("GetMessageW")
	procDispatchMessage = user32.NewProc("DispatchMessageW")
	procPostQuitMessage = user32.NewProc("PostQuitMessage")
	procInvalidateRect  = user32.NewProc("InvalidateRect")
	procShowWindow      = user32.NewProc("ShowWindow")
	procUpdateWindow    = user32.NewProc("UpdateWindow")
	procDestroyWindow   = user32.NewProc("DestroyWindow")
	procBeginPaint      = user32.NewProc("BeginPaint")
	procEndPaint        = user32.NewProc("EndPaint")
	procFillRect        = user32.NewProc("FillRect")
	procCreateSolidBrush = gdi32.NewProc("CreateSolidBrush")
	procDeleteObject     = gdi32.NewProc("DeleteObject")
	procSelectObject     = gdi32.NewProc("SelectObject")
	procCreateFont       = gdi32.NewProc("CreateFontW")
	procSetTextAlign     = gdi32.NewProc("SetTextAlign")
	procTextOut          = gdi32.NewProc("TextOutW")
	procSetTextColor     = gdi32.NewProc("SetTextColor")
	procSetBkMode        = gdi32.NewProc("SetBkMode")
	procDwmSetWindowAttr = dwmapi.NewProc("DwmSetWindowAttribute")
)

// Window messages and Win32 style constants.
const (
	WM_DESTROY = 0x0002
	WM_PAINT   = 0x000F
	WM_CLOSE   = 0x0010

	CS_HREDRAW = 0x0002
	CS_VREDRAW = 0x0001

	FW_NORMAL = 400
	TRANSPARENT = 1
	TA_LEFT  = 0
	TA_CENTER = 6

	// DWM window corner preference (Windows 11 era; ignored on older builds).
	DWMWA_WINDOW_CORNER_PREFERENCE = 33
	DWMWCP_ROUND                   = 2

	// Window styles.
	wsOverlappedWindow = 0x00CF0000 // WS_OVERLAPPEDWINDOW (caption + sysmenu + minimize/maximize)
)

// PAINTSTRUCT used during WM_PAINT.
type paintStruct struct {
	Hdc         uintptr
	fErase      uint32
	rcLeft      int32
	rcTop       int32
	rcRight     int32
	rcBottom    int32
	fRestore    uint32
	fIncUpdate  uint32
	_           [32]byte
}

// WNDCLASSEX structure for RegisterClassExW.
type wndClassEx struct {
	Size       uint32
	Style      uint32
	WndProc    uintptr
	ClsExtra   int32
	WndExtra   int32
	Instance   uintptr
	Icon       uintptr
	Cursor     uintptr
	Background uintptr
	MenuName   *uint16
	ClassName  *uint16
	IconSm     uintptr
}

// Shared state between the UI thread and the update goroutine. Guarded by
// stateMu. The update goroutine writes step text and the stage index; the UI
// thread reads them in WM_PAINT.
var (
	stateMu      sync.Mutex
	currentStep  string
	currentStage int
	totalStages  = 5
	updateErr    error
	updateDone   bool
	exitScheduled bool

	globalHwnd uintptr

	// GDI handles created once in runWithWindow and deleted at exit.
	brushBg    uintptr // window background (light)
	brushBarBg uintptr // progress bar track (muted)
	brushBarFg uintptr // progress bar fill (accent blue)
	fontBrand  uintptr // YaHei UI 22 bold  - the 云卷 wordmark
	fontTitle  uintptr // YaHei UI 17 bold  - 正在更新
	fontBody   uintptr // YaHei UI 13       - step label and footer
)

// runWithWindow creates the progress window, runs the update on a goroutine,
// and pumps messages until the update completes. Blocks until done, then exits.
func runWithWindow(zipPath, installDir string, oldPID int, exeName string) {
	// Colors use Win32 BGR (0x00BBGGRR), so convert from RGB.
	brushBg = createBrush(0x00F8F8F8)    // #F8F8F8 light background
	brushBarBg = createBrush(0x00E4E4E7) // #E4E4E7 muted track
	brushBarFg = createBrush(0x00EB6325) // #2563EB accent blue (BGR)

	fontBrand = createFont("Microsoft YaHei UI", 22, true)
	fontTitle = createFont("Microsoft YaHei UI", 17, true)
	fontBody = createFont("Microsoft YaHei UI", 13, false)

	// Create the window FIRST so globalHwnd is set and the message pump can
	// process WM_PAINT before the update goroutine starts sending status
	// callbacks. If we start the goroutine before the window exists, a fast
	// update can finish before the first GetMessage, and invalidate() calls
	// become no-ops (globalHwnd == 0), leaving the window blank or unseen.
	hwnd := createUpdaterWindow()
	if hwnd == 0 {
		logf("ERROR: could not create updater window, exiting")
		os.Exit(1)
	}

	// Now that the window is visible and the pump is about to start, launch
	// the update on a background goroutine. Status callbacks trigger repaints.
	go func() {
		err := performUpdate(zipPath, installDir, oldPID, exeName, func(msg string) {
			stateMu.Lock()
			currentStep = msg
			currentStage++
			if currentStage > totalStages {
				currentStage = totalStages
			}
			stateMu.Unlock()
			invalidate()
		})
		stateMu.Lock()
		updateErr = err
		updateDone = true
		stateMu.Unlock()
		invalidate()
	}()

	pumpMessages()
}

// createBrush wraps CreateSolidBrush and returns the handle.
func createBrush(color uintptr) uintptr {
	r, _, _ := procCreateSolidBrush.Call(color)
	return r
}

// createFont wraps CreateFontW. height is interpreted as a point size (we pass
// it negative so the font mapper treats it as points and scales for DPI).
func createFont(faceName string, pointSize int32, bold bool) uintptr {
	weight := int32(FW_NORMAL)
	if bold {
		weight = 700
	}
	wide, _ := syscall.UTF16PtrFromString(faceName)
	r, _, _ := procCreateFont.Call(
		uintptr(-pointSize), // negative = point size
		0, 0, 0,             // width, escapement, orientation
		uintptr(weight),     // weight
		0, 0, 0,             // italic, underline, strikeOut
		1,                   // DEFAULT_CHARSET
		0, 0, 0,             // outPrecision, clipPrecision, quality
		0,                   // pitchAndFamily
		uintptr(unsafe.Pointer(wide)),
	)
	return r
}

// invalidate triggers a full repaint of the window.
func invalidate() {
	if globalHwnd != 0 {
		procInvalidateRect.Call(globalHwnd, 0, 1)
	}
}

// createUpdaterWindow registers the class and creates the window.
func createUpdaterWindow() uintptr {
	className, _ := syscall.UTF16PtrFromString("CloudVolumeUpdaterClass")
	title, _ := syscall.UTF16PtrFromString("云卷更新")
	hInst, _, _ := procGetModuleHandle.Call(0)

	wc := wndClassEx{
		Size:       uint32(unsafe.Sizeof(wndClassEx{})),
		Style:      CS_HREDRAW | CS_VREDRAW,
		WndProc:    syscall.NewCallback(windowProc),
		Instance:   hInst,
		Background: brushBg,
		ClassName:  className,
	}
	procRegisterClassEx.Call(uintptr(unsafe.Pointer(&wc)))

	// Window size 460x260, centered by CW_USEDEFAULT.
	hwnd, _, _ := procCreateWindowEx.Call(
		0x00000008, // WS_EX_TOPMOST so it stays above the closing app
		uintptr(unsafe.Pointer(className)),
		uintptr(unsafe.Pointer(title)),
		wsOverlappedWindow,
		0x80000000, 0x80000000, // CW_USEDEFAULT for x, y
		460, 260,
		0, 0, hInst, 0,
	)
	globalHwnd = hwnd
	if hwnd == 0 {
		return 0
	}

	// Request rounded corners (only effective on Windows 11; ignored elsewhere).
	pref := int32(DWMWCP_ROUND)
	procDwmSetWindowAttr.Call(hwnd, DWMWA_WINDOW_CORNER_PREFERENCE,
		uintptr(unsafe.Pointer(&pref)), unsafe.Sizeof(pref))

	procShowWindow.Call(hwnd, 5) // SW_SHOW
	procUpdateWindow.Call(hwnd)
	return hwnd
}

// windowProc is the window procedure for the updater window.
func windowProc(hwnd, msg, wParam, lParam uintptr) uintptr {
	switch msg {
	case WM_PAINT:
		onPaint(hwnd)
		return 0
	case WM_DESTROY:
		procPostQuitMessage.Call(0)
		return 0
	case WM_CLOSE:
		// Block manual close while the update is still running; allow it once
		// the update is done so the auto-destroy in the pump succeeds.
		stateMu.Lock()
		done := updateDone
		stateMu.Unlock()
		if !done {
			return 0
		}
	}
	r, _, _ := procDefWindowProc.Call(hwnd, msg, wParam, lParam)
	return r
}

// onPaint draws the full window content.
func onPaint(hwnd uintptr) {
	var ps paintStruct
	hdc, _, _ := procBeginPaint.Call(hwnd, uintptr(unsafe.Pointer(&ps)))
	if hdc == 0 {
		return
	}
	defer procEndPaint.Call(hwnd, uintptr(unsafe.Pointer(&ps)))

	stateMu.Lock()
	step := currentStep
	stage := currentStage
	err := updateErr
	done := updateDone
	stateMu.Unlock()

	// All text is horizontally centered at window center x=230.
	const cx = 230

	// Brand wordmark.
	drawText(hdc, fontBrand, "云卷", 0x00202020, cx, 30, TA_CENTER)
	// Title.
	drawText(hdc, fontTitle, "正在更新", 0x00404040, cx, 70, TA_CENTER)

	// Step label.
	label := step
	if label == "" {
		label = "准备中..."
	}
	if done && err != nil {
		label = "更新失败：" + err.Error()
	} else if done {
		label = "更新完成"
	}
	drawText(hdc, fontBody, label, 0x00606060, cx, 108, TA_CENTER)

	// Segmented progress bar across the window.
	barLeft, barRight := 40, 420
	barTop, barBottom := 158, 170
	gap := 6
	segWidth := (barRight - barLeft - gap*(totalStages-1)) / totalStages
	for i := 0; i < totalStages; i++ {
		x := barLeft + i*(segWidth+gap)
		rect := [4]int32{int32(x), int32(barTop), int32(x + segWidth), int32(barBottom)}
		brush := brushBarBg
		if i < stage {
			brush = brushBarFg
		}
		if done {
			if err == nil {
				brush = brushBarFg
			} else {
				brush = brushBarBg
			}
		}
		procFillRect.Call(hdc, uintptr(unsafe.Pointer(&rect[0])), brush)
	}

	// Footer hint.
	footer := "请勿关闭此窗口，更新完成后将自动启动"
	if done && err != nil {
		footer = "更新失败，请将日志发送给开发者排查"
	}
	drawText(hdc, fontBody, footer, 0x00909090, cx, 192, TA_CENTER)
}

// drawText selects a font, sets color/background mode/alignment, draws text at
// (x, y), and restores the previously selected font. color is 0x00BBGGRR.
func drawText(hdc, font uintptr, text string, color uintptr, x, y int32, align uintptr) {
	oldFont, _, _ := procSelectObject.Call(hdc, font)
	defer procSelectObject.Call(hdc, oldFont)
	procSetBkMode.Call(hdc, TRANSPARENT)
	procSetTextColor.Call(hdc, color)
	procSetTextAlign.Call(hdc, align)
	wide, _ := syscall.UTF16PtrFromString(text)
	procTextOut.Call(hdc, uintptr(x), uintptr(y),
		uintptr(unsafe.Pointer(wide)), uintptr(len([]rune(text))))
}

// pumpMessages runs the Win32 message loop until WM_QUIT, then cleans up and
// exits the process with the right status code.
func pumpMessages() {
	var msg [28]byte // MSG struct
	for {
		ret, _, _ := procGetMessage.Call(uintptr(unsafe.Pointer(&msg[0])), 0, 0, 0)
		if ret == 0 { // WM_QUIT
			break
		}
		if ret == 0xFFFFFFFF { // error
			break
		}
		procDispatchMessage.Call(uintptr(unsafe.Pointer(&msg[0])))

		// Once the update is done, schedule a delayed window destroy so the
		// user briefly sees the final state before the updater exits.
		stateMu.Lock()
		done := updateDone
		stateMu.Unlock()
		if done && !exitScheduled {
			exitScheduled = true
			// On error, hold the window longer so the user can read the message.
			// On success, 2s is enough since the new app is already visible.
			stateMu.Lock()
			hadErr := updateErr != nil
			stateMu.Unlock()
			delay := 2 * time.Second
			if hadErr {
				delay = 15 * time.Second
			}
			go func() {
				time.Sleep(delay)
				procDestroyWindow.Call(globalHwnd)
			}()
		}
	}

	// Release GDI resources.
	procDeleteObject.Call(brushBg)
	procDeleteObject.Call(brushBarBg)
	procDeleteObject.Call(brushBarFg)
	procDeleteObject.Call(fontBrand)
	procDeleteObject.Call(fontTitle)
	procDeleteObject.Call(fontBody)

	if updateErr != nil {
		logf("updater exiting with error: %v", updateErr)
		os.Exit(1)
	}
	logf("updater exiting successfully")
	os.Exit(0)
}

// fail is used by the headless (non-Windows or fallback) path. The windowed
// path shows errors in the UI instead of using this.
func fail(msg string, err error) {
	logf("FATAL: %s: %v", msg, err)
	fmt.Fprintf(os.Stderr, "%s: %v\n", msg, err)
	os.Exit(1)
}
