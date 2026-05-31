{{flutter_js}}
{{flutter_build_config}}

const bootShell = document.getElementById('boot-shell');
const bootStatusText = document.getElementById('boot-status-text');
const bootStatusPercent = document.getElementById('boot-status-percent');

function setBootStatus(text, percent) {
  if (bootStatusText) {
    bootStatusText.textContent = text;
  }
  if (bootStatusPercent) {
    bootStatusPercent.textContent = `${percent}%`;
  }
}

setBootStatus('正在准备界面资源', 18);

_flutter.loader.load({
  onEntrypointLoaded: async function(engineInitializer) {
    setBootStatus('正在初始化渲染引擎', 56);
    const appRunner = await engineInitializer.initializeEngine();
    setBootStatus('正在启动 Cloud Volume', 82);
    await appRunner.runApp();
    setBootStatus('即将进入控制台', 100);
    window.addEventListener(
      'flutter-first-frame',
      function () {
        if (bootShell) {
          bootShell.classList.add('boot-shell--done');
        }
      },
      { once: true },
    );
  },
});
