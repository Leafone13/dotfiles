# dotfiles

Мой личный слой поверх [Omarchy](https://omarchy.org), управляется [chezmoi](https://chezmoi.io).
Один репозиторий для двух задач: перенести мои настройки на новую машину и настроить любой девпод.

Ниже — **по целям**. Каждый раздел самодостаточный: команды повторяются, если нужны в разных ситуациях.

- [Перенести всё на новую машину](#перенести-всё-на-новую-машину)
- [Поменял настройку на хосте — сохранить в репозиторий](#поменял-настройку-на-хосте--сохранить-в-репозиторий)
- [Подтянуть изменения из репозитория (сделанные на другой машине)](#подтянуть-изменения-из-репозитория)
- [Создать девпод для проекта](#создать-девпод-для-проекта)
- [Работать в девподе](#работать-в-девподе)
- [Обновить девпод после изменений в dotfiles](#обновить-девпод-после-изменений-в-dotfiles)
- [Поправить dotfiles изнутри девпода](#поправить-dotfiles-изнутри-девпода)
- [Добавить инструмент](#добавить-инструмент)
- [После `omarchy update`](#после-omarchy-update)
- [Что-то сломалось / откатить](#что-то-сломалось--откатить)
- [Как это устроено](#как-это-устроено)

---

## Перенести всё на новую машину

1. Установить Omarchy как обычно.
2. Войти в GitHub (репозиторий приватный) и применить dotfiles:

   ```bash
   mise use -g gh chezmoi          # временно; dotfiles потом заменят mise-конфиг своим
   gh auth login                   # аккаунт Leafone13, HTTPS, через браузер
   gh auth setup-git
   chezmoi init --apply Leafone13  # спросит "Work machine?" — Enter = да (anydesk, balena-cli)
   ```

   chezmoi разложит файлы и сам запустит настройку хоста: пакеты, ssh-agent, группа docker,
   плагин hyprexpo, DevPod. Если какой-то шаг пропущен (например, Hyprland не был запущен) —
   просто ещё раз `chezmoi apply`, шаги можно повторять безопасно.

3. Перенести SSH-ключи со старой машины (в репозитории их нет и не будет):

   ```bash
   scp 'old-host:~/.ssh/id_ed25519_*' ~/.ssh/
   mkdir -p -m 700 ~/.ssh/config.d
   scp old-host:~/.ssh/config.d/yaya ~/.ssh/config.d/   # рабочие хосты (alan, pi-bojan)
   chmod 600 ~/.ssh/id_ed25519_* ~/.ssh/config.d/yaya
   ```

4. Диктовка (voxtype) — ставит Omarchy, у меня только свой конфиг (модель `small`, язык auto):

   ```bash
   omarchy voxtype install
   chezmoi apply                   # вернёт мой config.toml поверх стандартного
   voxtype setup --download        # скачает модель из моего конфига
   ```

5. Перелогиниться (группа docker и ssh-agent подхватятся в новой сессии).

6. Проверить:

   ```bash
   chezmoi verify && echo OK       # всё на диске совпадает с репозиторием
   ssh -T git@github.com           # спросит пароль ключа один раз → "Hi serhii-yaya!"
   ```

---

## Поменял настройку на хосте — сохранить в репозиторий

Посмотреть, что изменилось по сравнению с репозиторием:

```bash
chezmoi status
chezmoi diff
```

**Обычный файл, уже в репозитории** (bindings.lua, tmux.conf, nvim/…):

```bash
chezmoi re-add
chezmoi git -- add -A
chezmoi git -- commit -m "что поменял"
chezmoi git -- push
```

**Файл-шаблон** — `re-add` их не трогает, правь сразу шаблон:
`~/.bashrc`, `~/.config/git/config`, `~/.config/mise/config.toml`, `~/.config/nvim/lua/plugins/theme.lua`.

```bash
chezmoi edit ~/.bashrc          # откроет шаблон в $EDITOR
chezmoi apply ~/.bashrc
chezmoi git -- add -A
chezmoi git -- commit -m "что поменял"
chezmoi git -- push
```

**Новый файл:**

```bash
chezmoi add ~/.config/что-то/файл
chezmoi git -- add -A
chezmoi git -- commit -m "добавил файл"
chezmoi git -- push
```

Если файл только для рабочего стола (Hyprland, шрифты, GUI-приложения) — он не должен
попасть в девподы: `chezmoi cd`, допиши путь в `.chezmoiignore` в блок `if not .omarchy`, `exit`.

---

## Подтянуть изменения из репозитория

Сделал изменения на другой машине и запушил — применить здесь:

```bash
chezmoi update                  # git pull + apply
```

Осторожный вариант (сначала посмотреть):

```bash
chezmoi git -- pull
chezmoi diff
chezmoi apply
```

---

## Создать девпод для проекта

Dotfiles подтянутся сами (DevPod настроен на `Leafone13/dotfiles` при настройке хоста).

1. В папке проекта `.devcontainer/devcontainer.json`, минимум:

   ```json
   {
     "name": "my-project",
     "image": "mcr.microsoft.com/devcontainers/base:ubuntu-24.04",
     "remoteUser": "vscode"
   }
   ```

2. Инструменты проекта (с версиями!) — в `mise.toml` в корне проекта:

   ```toml
   [tools]
   kubectl = "1.31"
   helm = "3.16"
   ```

3. Поднять и зайти:

   ```bash
   devpod up ~/Work/devpods/my-project --ide none
   devpod ssh my-project
   ```

4. Внутри, один раз — поставить инструменты проекта:

   ```bash
   cd /workspaces/my-project
   mise trust && mise install
   ```

Песочница для экспериментов уже есть: `~/Work/devpods/test`.

---

## Работать в девподе

Девпод ведёт себя как сервер: tmux и vim там **стандартные**, без моих биндов.
Мои — только bash (окружение Omarchy) и Neovim.

```bash
devpod ssh my-project           # или: ssh my-project.devpod
devpod up ~/Work/devpods/my-project --ide none   # если остановлен — поднимет
devpod stop my-project
devpod ls
```

tmux внутри, если сижу в tmux на хосте (вложенный): префикс внутреннего — `Ctrl+b Ctrl+b`.

```bash
tmux new -s work                # долгие задачи переживут отключение
tmux a                          # вернуться
```

---

## Обновить девпод после изменений в dotfiles

Сначала изменения должны быть запушены (см. «Поменял настройку на хосте»). Дальше одно из двух.

**Быстро, изнутри девпода:**

```bash
devpod ssh my-project
chezmoi update
```

**Начисто** (пересоздать контейнер; код проекта на хосте не пострадает, домашняя папка контейнера — да):

```bash
devpod up ~/Work/devpods/my-project --ide none --recreate
```

---

## Поправить dotfiles изнутри девпода

В девподе репозиторий лежит в `~/dotfiles` (chezmoi знает об этом).

```bash
chezmoi edit ~/.config/nvim/lua/config/keymaps.lua
chezmoi apply
chezmoi git -- add -A
chezmoi git -- commit -m "что поменял"
chezmoi git -- push             # доступ к GitHub пробрасывает DevPod
```

На хосте потом: `chezmoi update`.

---

## Добавить инструмент

**Во все девподы** (мой личный набор):

```bash
chezmoi edit ~/.config/mise/config.toml   # вторая половина файла (после else)
chezmoi git -- add -A
chezmoi git -- commit -m "devpods: +tool"
chezmoi git -- push
# в девподе: chezmoi update  (mise install запустится сам)
```

**Только в одном проекте** — в `mise.toml` проекта, внутри девпода:

```bash
mise use tool@1.2
```

**На хосте:**

```bash
chezmoi edit ~/.config/mise/config.toml   # первая половина файла (if .omarchy)
chezmoi apply                             # mise install запустится сам
chezmoi git -- add -A
chezmoi git -- commit -m "host: +tool"
chezmoi git -- push
```

**Системный пакет (pacman/AUR) на хосте:** допиши его в `.chezmoiscripts/run_onchange_after_omarchy-host-setup.sh.tmpl`
(`chezmoi cd`), потом `chezmoi apply` и коммит.

---

## После `omarchy update`

1. Omarchy мог изменить файлы, которые веду я — проверить и вернуть свои:

   ```bash
   chezmoi diff
   chezmoi apply
   ```

2. Обновить снимок bash-окружения Omarchy для девподов:

   ```bash
   chezmoi cd
   ./scripts/sync-omarchy
   git diff --stat
   git add -A && git commit -m "sync Omarchy bash snapshot" && git push
   exit
   ```

---

## Что-то сломалось / откатить

**Вернуть файл к версии из репозитория** (выбросить локальные правки):

```bash
chezmoi diff ~/.config/hypr/bindings.lua
chezmoi apply ~/.config/hypr/bindings.lua
```

**`omarchy refresh …` сбросил мой конфиг:**

```bash
chezmoi apply
```

**Посмотреть, что сделает apply, ничего не меняя:**

```bash
chezmoi apply --dry-run -v
```

**Откатить последний коммит в репозитории:**

```bash
chezmoi git -- revert HEAD
chezmoi apply
chezmoi git -- push
```

---

## Как это устроено

chezmoi сам определяет, где он (`.chezmoi.toml.tmpl`): `omarchy`, `container`, `work`.

| Слой | Где | Что |
|---|---|---|
| Omarchy | хост | всё по умолчанию (не в этом репозитории) |
| **Этот репозиторий, хост** | хост | мои правки: Hyprland, раскладки, fcitx5, tmux, nvim, git, ssh config, mise, скрипты |
| **Этот репозиторий, девпод** | контейнер | bash (снимок окружения Omarchy), nvim, git, mise-набор; vim/tmux стандартные из apt |
| Рабочий | `~/.ssh/config.d/yaya` | хосты YaYa — не здесь |
| Проект | `mise.toml`, `.devcontainer/` | инструменты и версии проекта |
| Нигде | — | SSH-ключи, токены, пароли |

Git-почта выбирается по адресу репозитория: `serhii-yaya/*` → рабочая, всё остальное → личная.

| Файл | Зачем |
|---|---|
| `install` | вход для DevPod: apt-пакеты, chezmoi, apply из клона |
| `.chezmoiscripts/…mise-install…` | `mise install` при изменении mise-конфига |
| `.chezmoiscripts/…omarchy-host-setup…` | настройка хоста, которая не файлы (пакеты, ssh-agent, docker, hyprexpo, DevPod) |
| `scripts/sync-omarchy` | обновить снимок bash-окружения Omarchy |
| `dot_local/share/omarchy/` | сам снимок (только для девподов) |
