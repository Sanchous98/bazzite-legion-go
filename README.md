# bazzite-legion-go

Кастомный OCI-образ поверх `ghcr.io/ublue-os/bazzite-deck`, заточенный под Lenovo Legion Go (Ryzen Z1 Extreme, Zen 4).

## Что отличается от stock Bazzite

- **Ядро**: `kernel-cachyos-deckify` (handheld-вариант CachyOS с BORE + handheld-патчами) с fallback на `kernel-cachyos-handheld` → `kernel-cachyos`, из COPR `bieszczaders/kernel-cachyos`.
- **Собственная пересборка mesa и ffmpeg** с `-O3 -march=x86-64-v4 -mtune=znver4 -flto=auto -fno-plt -fno-semantic-interposition` — отдельный `v4-builder` стейдж в `Containerfile` собирает их из оригинальных SRPM (Terra для mesa, negativo17 для ffmpeg) и прокидывает готовые `.rpm` в финальный образ, где `rpm-ostree override replace` ставит их поверх stock.
- **Флаги сборки**: `/etc/profile.d/zz-x86-64-v4.sh` задаёт `-O3 -march=x86-64-v4 -mtune=znver4 -flto=auto` для локальных компиляций (user builds, flatpak overrides).
- **acpi_call kmod**: пересобран под `kernel-cachyos` в image build — нужен HHD для управления TDP на Legion Go.
- **Параметры ядра**: `amd_pstate=active`, `amdgpu.sg_display=0`, `split_lock_detect=off`, `rcu_nocbs=0-15`, `rcutree.enable_rcu_lazy=1` (5–10% экономии батареи на idle), `mitigations=off` (CPU-митигации Spectre/Meltdown/MDS отключены ради производительности — оправданно на single-user gaming handheld, не для рабочих машин).
- **Sysctl**: применён апстрим `70-cachyos-settings.conf` — `vm.swappiness=100`, `vm.vfs_cache_pressure=50`, `vm.dirty_bytes`, `kernel.nmi_watchdog=0` и прочее (см. `build_files/60-sysctl.sh`).
- **Proton-CachyOS**: последняя версия автоматически распаковывается в `/usr/share/steam/compatibilitytools.d/` во время сборки образа; Steam подхватывает её без ручной установки.

> HHD, ryzenadj, power-profiles-daemon в bazzite-deck уже есть — не дублируем.

## Структура

```
Containerfile              # multi-stage: v4-builder (пересборка mesa/ffmpeg) + final
build_files/
  build.sh                 # оркестратор
  10-repos.sh              # COPR с kernel-cachyos
  20-kernel.sh             # rpm-ostree override replace на kernel-cachyos
  25-acpi-call.sh          # akmod-acpi_call под наше ядро (TDP в HHD)
  30-v4-local.sh           # установка v4-mesa/ffmpeg из /ctx/v4-rpms
  40-legion-go.sh          # kargs под Legion Go
  50-proton.sh             # предзагрузка Proton-CachyOS (стабильная папка)
  60-sysctl.sh             # sysctl-тюнинг из CachyOS-Settings
  70-image-info.sh         # правит /usr/share/ublue-os/image-info.json
  99-cleanup.sh            # очистка /var перед commit
.github/workflows/
  build.yml                # сборка и publish OCI-образа
  iso.yml                  # сборка установочного ISO из уже опубликованного образа
cosign.pub                 # публичный ключ для верификации подписи
```

## Первоначальная настройка

1. Форкнуть/создать репозиторий на GitHub с этим содержимым.
2. Сгенерировать ключи cosign и положить:
   - приватный → GitHub secret `SIGNING_SECRET`;
   - публичный → `cosign.pub` в репозитории.
   ```
   cosign generate-key-pair
   ```
3. Убедиться, что GitHub Actions имеет права `packages: write` (включено в workflow).
4. Пуш в `main` → GHA соберёт и запушит образ в `ghcr.io/<owner>/bazzite-legion-go:latest`.

## Установка на Legion Go

На уже установленной Bazzite (или другой ublue-образ) выполнить:

```bash
sudo bootc switch ghcr.io/<owner>/bazzite-legion-go:latest
sudo systemctl reboot
```

Либо старым API, если система ещё на `rpm-ostree`:

```bash
sudo rpm-ostree rebase ostree-image-signed:docker://ghcr.io/<owner>/bazzite-legion-go:latest
sudo systemctl reboot
```

Откат — `sudo bootc rollback` или `sudo rpm-ostree rollback`.

## Установочный ISO

Для чистой установки с нуля (а не rebase с существующей Bazzite) собирается ISO через `bootc-image-builder`.

- **Запуск вручную**: вкладка Actions → workflow *build-iso* → Run workflow, опционально указать tag образа (по умолчанию `stable`).
- **По расписанию**: автоматически 1-го числа каждого месяца в 08:00 UTC.
- **Результат**: ISO + `.sha256` кладутся в workflow artifacts (`bazzite-legion-go-<tag>-<дата>.iso`), хранятся 14 дней.

Устанавливается как обычный Fedora-ISO через Anaconda: выбор диска, заведение пользователя в OOBE. После первой загрузки — стандартный `bootc upgrade` для апдейтов.

## Что может сломаться

- **Kernel override** привязан к списку пакетов `kernel*`, который поставляет Bazzite. При крупных апстрим-изменениях состав `kernel-modules-*` может поменяться — `20-kernel.sh` придётся править.
- **kernel-cachyos-handheld** может отсутствовать в COPR на момент сборки — скрипт автоматически откатится на `kernel-cachyos`.
- **Terra пакеты** иногда отстают по версиям от Fedora — если замена ломает зависимости, конкретный пакет надо убрать из списка в `30-v4-packages.sh`.
- **AVX-512 на Zen 4** реализован как double-pumped 256-bit. На некоторых AVX-512-heavy workload'ах выигрыш от v4 минимальный или отрицательный из-за снижения частоты. Бенчите конкретные игры.

## TODO

- [ ] Проверить работу kernel override на актуальной Bazzite (F41+).
- [ ] Добавить `ublue-os/akmods` если понадобятся OOT-модули.
