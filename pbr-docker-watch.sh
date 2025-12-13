#!/bin/bash

# Следим за событиями Docker и обновляем PBR при старте контейнеров

echo "Запуск мониторинга Docker событий..."

docker events --filter 'event=start' --filter 'type=container' --format '{{.Actor.Attributes.name}}' | while read container; do
    # Проверяем, что это наш контейнер
    if [[ "$container" == remnanode* ]]; then
        echo "$(date): Обнаружен старт контейнера $container"
        sleep 3  # Ждём пока сеть полностью поднимется
        /opt/setup-pbr.sh
    fi
done
