#!/usr/bin/env bash
set -euo pipefail

# 看看生产备份。由 systemd timer 调用，也可手动执行：
#   backup_production.sh db      # PostgreSQL，每日
#   backup_production.sh media   # uploads 卷，每周

mode="${1:-db}"
backup_root="/home/ubuntu/kankan/backups"
postgres_container="ccpj_postgres_prod"
backend_container="ccpj_backend"
stamp="$(date -u +%Y%m%dT%H%M%SZ)"

case "$mode" in
  db)
    backup_dir="$backup_root/postgres"
    mkdir -p "$backup_dir"
    partial="$backup_dir/.daily-$stamp.dump.partial"
    final="$backup_dir/daily-$stamp.dump"
    trap 'rm -f -- "$partial"' EXIT
    docker exec "$postgres_container" sh -c \
      'pg_dump -Fc -U "$POSTGRES_USER" "$POSTGRES_DB"' > "$partial"
    test -s "$partial"
    docker exec -i "$postgres_container" pg_restore --list < "$partial" >/dev/null
    chmod 600 "$partial"
    mv -- "$partial" "$final"
    trap - EXIT
    # 只清理由本脚本生成且超过 30 天的 daily 文件；人工 checkpoint 永不碰。
    find "$backup_dir" -maxdepth 1 -type f -name 'daily-*.dump' -mtime +30 -delete
    echo "database backup verified: $final"
    ;;
  media)
    backup_dir="$backup_root/media"
    mkdir -p "$backup_dir"
    partial="$backup_dir/.weekly-$stamp.tar.zst.partial"
    final="$backup_dir/weekly-$stamp.tar.zst"
    trap 'rm -f -- "$partial"' EXIT
    docker exec "$backend_container" tar -C /srv/app -cf - uploads \
      | zstd -T0 -3 -q -o "$partial"
    test -s "$partial"
    zstd -q -t "$partial"
    chmod 600 "$partial"
    mv -- "$partial" "$final"
    trap - EXIT
    # 只清理由本脚本生成且超过 21 天的 weekly 文件（通常保留三周）。
    find "$backup_dir" -maxdepth 1 -type f -name 'weekly-*.tar.zst' -mtime +21 -delete
    echo "media backup verified: $final"
    ;;
  *)
    echo "usage: $0 {db|media}" >&2
    exit 2
    ;;
esac
