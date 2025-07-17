#!/bin/bash
set -e

if [ "$EUID" -ne 0 ]; then
  echo "Этот скрипт нужно запускать от root (sudo)"
  exit 1
fi

echo "[1/8] Обновление системы"
pacman -Syu --noconfirm

echo "[2/8] Установка необходимых пакетов (если не установлены)"
pacman -S --needed --noconfirm systemd-zram-generator

echo "[3/8] Настройка systemd journal: только в RAM"
mkdir -p /etc/systemd/journald.conf.d
cat <<EOF > /etc/systemd/journald.conf.d/volatile.conf
[Journal]
Storage=volatile
EOF

echo "[4/8] Настройка zram (сжатый swap в RAM)"
mkdir -p /etc/systemd/zram-generator.conf.d
cat <<EOF > /etc/systemd/zram-generator.conf.d/zram.conf
[zram0]
zram-size = ram
compression-algorithm = zstd
EOF

echo "[5/8] Настройка tmpfs для /tmp, /var/tmp и /var/log"
grep -q '/tmp tmpfs' /etc/fstab || cat <<EOF >> /etc/fstab

# tmpfs для уменьшения записи на флешку
tmpfs /tmp tmpfs defaults,noatime,mode=1777 0 0
tmpfs /var/tmp tmpfs defaults,noatime,mode=1777 0 0
tmpfs /var/log tmpfs defaults,noatime,mode=0755 0 0
EOF

echo "[6/8] Заменяем relatime на noatime,nodiratime,discard в fstab"
sed -i 's/relatime/noatime,nodiratime,discard/g' /etc/fstab || true

echo "[7/8] Чистка кэша pacman"
pacman -Scc --noconfirm

echo "[8/8] Проверка и удаление лишних пакетов (если есть)"
for pkg in geoclue packagekit tracker modemmanager zeitgeist; do
  if pacman -Qs "$pkg" > /dev/null; then
    echo "Удаление $pkg"
    pacman -Rns --noconfirm "$pkg"
  fi
done

echo "Готово. Arch оптимизирован для запуска с флешки. Перезагрузка настоятельно рекомендуется."