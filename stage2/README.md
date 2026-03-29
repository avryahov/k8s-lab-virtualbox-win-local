# Kubernetes Cluster Lab — Stage 2 (Production-Ready)

> **Это Stage 2.** Полноценная продакшн-конфигурация: SSH-ключи, .env-переменные,
> NSIS-визард для Windows, прокси-скрипт с флагами.
>
> Если ты только начинаешь — сначала пройди `../stage1/` (хардкодом, проще).

---

## Что добавляет Stage 2 по сравнению с Stage 1

| Возможность | Stage 1 | Stage 2 |
|-------------|---------|---------|
| Конфигурация | Хардкод в Vagrantfile | Переменные в .env |
| SSH | Пароль vagrant/vagrant | Ed25519-ключи (без пароля) |
| Запуск | `vagrant up` или launch.bat | NSIS-визард или proxy-launch.bat |
| Число воркеров | Всегда 2 | 1–4 (задаётся в .env) |
| CPU/RAM | Жёстко зашиты | Настраивается в .env |
| Подсеть | Всегда 192.168.56.x | Любая host-only подсеть |
| Безопасность | Фиктивные пароли | SSH-ключи + Windows ACL |

---

## Быстрый старт

### Вариант А: NSIS-визард (для школьников и новичков)

1. Установи NSIS: `winget install NSIS.NSIS`
2. Открой PowerShell в папке `stage2/installer/`:
   ```powershell
   makensis k8s-lab.nsi
   ```
3. Запусти получившийся `k8s-lab-setup.exe`
4. Следуй шагам визарда (выбор языка, параметры кластера, папка)
5. Нажми «Установить» — всё остальное автоматически

### Вариант Б: proxy-launch.bat (быстрый запуск)

```powershell
# Из корня проекта stage2/
.\proxy-launch.bat
# Или с кастомными параметрами:
.\proxy-launch.bat --workers=1 --cpus=2 --memory=2048
.\proxy-launch.bat --prefix=mylab --workers=3 --cpus=4 --memory=4096
```

### Вариант В: Ручной запуск (классика)

```powershell
# 1. Создай .env из шаблона
copy .env.example .env

# 2. Отредактируй .env под свои нужды (необязательно)
notepad .env

# 3. Запусти кластер
vagrant up

# 4. Проверь
vagrant ssh lab-k8s-master -- kubectl get nodes -o wide
```

---

## Параметры proxy-launch.bat

```
proxy-launch.bat [опции]

Опции:
  --prefix=NAME       Префикс имён ВМ          (default: lab-k8s)
  --workers=N         Количество воркеров 1-4  (default: 2)
  --cpus=N            CPU на каждую ВМ         (default: 2)
  --memory=MB         RAM в МБ на ВМ           (default: 2048)
  --subnet=X.X.X      Первые три октета        (default: 192.168.56)
  --k8s-version=V     Версия Kubernetes        (default: 1.34)
  --halt              Остановить кластер
  --destroy           Удалить кластер
  --status            Статус ВМ
  --help              Справка

Примеры:
  proxy-launch.bat --workers=1 --memory=2048        # минимальный кластер
  proxy-launch.bat --prefix=demo --workers=3        # 3 воркера с префиксом demo
  proxy-launch.bat --subnet=10.0.0                  # другая подсеть
```

---

## Структура файлов

```
stage2/
├── .env.example          ← Шаблон конфигурации (скопируй в .env)
├── .env                  ← Твоя конфигурация (НЕ в git!)
├── Vagrantfile           ← Автоматически читает .env
├── proxy-launch.bat      ← Быстрый запуск с флагами
├── README.md             ← Этот файл
│
├── scripts/
│   ├── common.sh             ← Подготовка всех нод
│   ├── master.sh             ← Инициализация control plane
│   ├── worker.sh             ← Подключение воркеров
│   ├── generate-node-key.ps1 ← Генерация ed25519 SSH-ключей
│   └── cleanup-node-key.ps1  ← Удаление ключей при vagrant destroy
│
└── installer/
    ├── k8s-lab.nsi           ← NSIS-скрипт (компилируй в .exe)
    └── lang/
        ├── russian.nsh       ← Строки на русском
        └── english.nsh       ← Строки на английском
```

---

## SSH-ключи (как работает)

Stage 2 автоматически генерирует SSH-ключи ed25519 для каждой ноды:

```
.vagrant/node-keys/
├── lab-k8s-master.ed25519      ← Приватный ключ (только у тебя)
├── lab-k8s-master.ed25519.pub  ← Публичный ключ (копируется в ВМ)
├── lab-k8s-worker1.ed25519
├── lab-k8s-worker1.ed25519.pub
├── lab-k8s-worker2.ed25519
└── lab-k8s-worker2.ed25519.pub
```

**Подключение без пароля:**
```powershell
ssh -i .vagrant\node-keys\lab-k8s-master.ed25519 -p 2232 vagrant@127.0.0.1
```

**Ключи удаляются автоматически** при `vagrant destroy` (триггер в Vagrantfile).

### Почему ed25519, а не RSA?

- RSA 2048: ~112 бит безопасности, медленный, ключ ~1800 байт
- Ed25519: ~128 бит безопасности, быстрый, ключ всего 32 байта
- Рекомендован: OpenSSH, GitHub, GitLab, NIST с 2014 года

Подробнее: `../docs/references.md` → раздел «SSH и криптография»

---

## Dashboard

- URL: **https://localhost:30443**
- Браузер: нажми «Дополнительно» → «Перейти» (самоподписанный сертификат — OK)
- Токен:
  ```powershell
  vagrant ssh lab-k8s-master -- kubectl -n kubernetes-dashboard create token admin-user --duration=24h
  ```

---

## Что изучить дальше

- `../docs/references.md` — академическая библиография
- `../docs/technologies.md` — описание каждой технологии
- `../docs/troubleshooting.md` — решение проблем
- `../stage1/` — более простой вариант без переменных
