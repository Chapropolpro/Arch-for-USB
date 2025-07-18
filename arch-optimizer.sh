#!/bin/bash
set -e

if [ "$EUID" -ne 0 ]; then
  echo "Этот скрипт нужно запускать от root (sudo)"
  exit 1
fi

echo "[1/8] Обновление системы"
pacman -Syu --noconfirm

echo "[2/8] Установка необходимых пакетов"
pacman -S --needed --noconfirm util-linux macchanger

echo "[3/8] Настройка systemd journal: только в RAM"
mkdir -p /etc/systemd/journald.conf.d
cat <<EOF > /etc/systemd/journald.conf.d/99-no-presistent.conf > /dev/null
[Journal]
Storage=volatile
SyncIntervalSec=10min
EOF
sudo systemctl restart systemd-journald

echo "[4/8] Настройка ZRAM"
# systemd unit
cat <<'EOF' > /etc/systemd/system/zram-swap.service
[Unit]
Description=ZRAM Swap
After=multi-user.target

[Service]
Type=oneshot
RemainAfterExit=true
ExecStart=/usr/local/bin/setup-zram.sh
ExecStop=/usr/bin/swapoff /dev/zram0

[Install]
WantedBy=multi-user.target
EOF

# Скрипт инициализации
cat <<'EOF' > /usr/local/bin/setup-zram.sh
#!/bin/bash
modprobe zram || exit 0
echo zstd > /sys/block/zram0/comp_algorithm
mem_total_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
echo $((mem_total_kb * 1024 / 2)) > /sys/block/zram0/disksize
mkswap /dev/zram0
swapon /dev/zram0
EOF

chmod +x /usr/local/bin/setup-zram.sh

# Активируем unit
systemctl daemon-reexec
systemctl daemon-reload
systemctl enable --now zram-swap.service

echo "[5/8] Настройка tmpfs для /tmp, /var/tmp, /var/log"
grep -q '/tmp tmpfs' /etc/fstab || cat <<EOF >> /etc/fstab

# tmpfs для уменьшения записи на диск
tmpfs /tmp      tmpfs defaults,noatime,mode=1777 0 0
tmpfs /var/tmp  tmpfs defaults,noatime,mode=1777 0 0
tmpfs /var/log  tmpfs defaults,noatime,mode=0755 0 0
EOF

echo "[6/8] Заменяем relatime на noatime,nodiratime,discard в fstab"
if grep -q 'relatime' /etc/fstab; then
  sed -i 's/\<relatime\>/noatime,nodiratime,discard/g' /etc/fstab
fi

echo "[7/8] Установка задержки сброса кэша на диск до 10 мин"
cat <<EOF > /etc/sysctl.d/98-zram-cache.conf
vm.dirty_writeback_centisecs = 60000
vm.dirty_expire_centisecs = 60000
vm.dirty_ratio = 40
vm.dirty_background_ratio = 10
EOF
sysctl --system

echo "[8/8] Очистка кэша pacman"
yes | pacman -Scc

echo "Готово. Arch оптимизирован под флешку."