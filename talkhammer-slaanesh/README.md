# TalkHammer: стадии порчи Slaanesh Expanded

Для десяти перечисленных в JSON действующих правительниц добавляет к отношению `50 × стадия порчи`: 0/50/100/150. Бонус применяется после культурного смягчения, до общего ограничения −250…+250. Вклад обычной дипломатии: `0.4 × отношение`, с пределами −40…+200.

При стадии 3 и вассалитете именно игроку добавляется инструкция согласиться на требования в текущем ответе, сохраняя возможность выразить недовольство или торговаться. Это инструкция модели: она не отменяет технические проверки движка и подтверждения сделок. Прежнего минимума отношения 0 и отдельного запрета выхода из вассалитета нет.

Сборка из корня репозитория: `node talkhammer-slaanesh/build.mjs [путь/к/talkhammer.pack]` (Node.js 24+). Нужен оригинальный [TalkHammer](https://steamcommunity.com/sharedfiles/filedetails/?id=3808547073). Пакет собирается без частных резервных копий. `installed-version-adjustments.json` сохраняет используемую версию обработчика диалога относительно более нового Workshop-модуля; хеши защищают от применения к несовместимому исходнику.

Установка при закрытой игре: пакет `00_talkhammer_slaanesh_diplomacy.pack` — в `data` с приоритетом выше TalkHammer; `talkhammer-slaanesh-rulers.json` — в папку `talkhammer` игры. Обновлять оба файла вместе.

Тесты требуют Python и Lupa (`python -m pip install lupa`). Для уже установленной Lupa в отдельной папке можно задать `TWW3_LUPA_PATH`.

```text
python talkhammer-slaanesh/test_policy.py talkhammer-slaanesh/00_talkhammer_slaanesh_diplomacy.pack
python talkhammer-slaanesh/regard-boundaries.test.py talkhammer-slaanesh/00_talkhammer_slaanesh_diplomacy.pack
```

Пакет воспроизводит установленный SHA-256 `a157b35790426f9bec019be8a3875fd6810f45d121f68d29a12fffb1c573b82c`. Проверены настоящие Lua-расчёты и условия инструкции. Живой диалог и исполнение сделки требуют отдельного игрового прогона.
