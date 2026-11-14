# TalkHammer → Codex

Мост для TalkHammer в Total War: WARHAMMER III. Читает задания игры из `talkhammer_data` и возвращает диалоги, сгенерированные Codex CLI. Работает вместо штатного TalkHammer Companion. Для этого режима Player2 не требуется.

1. Закрой штатный `TalkHammerCompanion.bat`, если он запущен.
2. Запусти `Start-TalkHammer-Codex.cmd` и оставь окно открытым.
3. В кампании открой **Дипломатия → SPEAK**. Для текстового режима можно выключить озвучку в настройках TalkHammer или командой `/tts off`.

По умолчанию запуск настроен для `D:\Steam\steamapps\common\Total War WARHAMMER III`. Для другой папки передай `-GameRoot`:

```powershell
.\Start-TalkHammer-Codex.cmd -GameRoot 'E:\SteamLibrary\steamapps\common\Total War WARHAMMER III'
```

Нужны Node.js 22 или новее и Codex CLI с активным входом. Запуск ищет их в PATH и в установке приложения Codex. Проверить авторизацию можно командой `codex login status`. Мост использует этот вход по HTTPS. Настройка подключения применяется только к запускам Codex из моста.

Чтобы вернуться к Player2, закрой окно моста и запусти штатный Companion. Не запускай оба моста на одной папке игры одновременно.
