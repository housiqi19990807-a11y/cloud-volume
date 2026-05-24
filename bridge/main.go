package main

/*
#include <stdlib.h>
*/
import "C"

import (
	"encoding/json"
	"strings"
	"unsafe"
)

// The Go bridge keeps the exported ABI narrow so Flutter only deals with JSON calls.
func main() {}

//export RemoteStorageInvoke
func RemoteStorageInvoke(method *C.char, args *C.char) *C.char {
	methodName := ""
	if method != nil {
		methodName = strings.TrimSpace(C.GoString(method))
	}

	rawArgs := ""
	if args != nil {
		rawArgs = C.GoString(args)
	}

	result, err := invokeBridgeMethod(methodName, json.RawMessage(rawArgs))
	if err != nil {
		return C.CString(buildErrorPayload(err))
	}
	return C.CString(buildSuccessPayload(result))
}

//export RemoteStorageFreeString
func RemoteStorageFreeString(value *C.char) {
	if value == nil {
		return
	}
	C.free(unsafe.Pointer(value))
}
