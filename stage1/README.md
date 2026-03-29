# Kubernetes Cluster — Stage 1 (Учебный)

> **Это Stage 1.** Всё хардкодом — IP-адреса, имена, версии прямо в файлах.
> Никаких паролей SSH, никаких переменных. Цель: запустить кластер и понять что происходит.
>
> Stage 2 (с SSH-ключами, NSIS-визардом, переменными) — в папке `../stage2/`.

---

## Что ты получишь

После запуска у тебя будет **настоящий кластер Kubernetes** из трёх виртуальных машин:

```
Твой компьютер (Windows)
│
├── VirtualBox
│   ├── k8s-master   192.168.56.10  ← управляет кластером
│   ├── k8s-worker1  192.168.56.11  ← запускает твои приложения
│   └── k8s-worker2  192.168.56.12  ← запускает твои приложения
│
└── Порты на localhost:
    ├── :2232  → SSH на мастер
    ├── :6443  → Kubernetes API
    └── :30443 → Веб-интерфейс Dashboard
```

---

## Требования

| Что нужно | Минимум | Где скачать |
|-----------|---------|-------------|
| Windows 10/11 | 64-bit | — |
| VirtualBox | 7.0+ | virtualbox.org/wiki/Downloads |
| Vagrant | 2.4+ | developer.hashicorp.com/vagrant/downloads |
| RAM компьютера | 8 ГБ | — |
| Место на диске | 20 ГБ | — |

**Проверь, что установлено.** Открой PowerShell и набери:
```powershell
vagrant --version     # должно быть: Vagrant 2.x.x
VBoxManage --version  # должно быть: 7.x.x
```

---

## Запуск (3 шага)

### Шаг 1 — Открой PowerShell в этой папке

Правой кнопкой на папке `stage1` → «Открыть в терминале»

Или в PowerShell вручную:
```powershell
cd C:\путь\до\проекта\stage1
```

### Шаг 2 — Запусти кластер

Вариант А — двойной клик на `launch.bat`

Вариант Б — в PowerShell:
```powershell
vagrant up
```

**Первый запуск займёт 15–30 минут.** Vagrant скачивает образ Ubuntu (~1.5 ГБ),
потом устанавливает Kubernetes на все три машины. Это нормально — выпей чай.

### Шаг 3 — Проверь что всё работает

```powershell
vagrant ssh k8s-master -- kubectl get nodes -o wide
```

Должно появиться что-то вроде:
```
NAME          STATUS   ROLES           AGE   VERSION   INTERNAL-IP
k8s-master    Ready    control-plane   5m    v1.34.6   192.168.56.10
k8s-worker1   Ready    <none>          3m    v1.34.6   192.168.56.11
k8s-worker2   Ready    <none>          3m    v1.34.6   192.168.56.12
```

Все три ноды `Ready` — кластер работает!

---

## Веб-интерфейс (Dashboard)

1. Открой браузер: **https://localhost:30443**
2. Браузер скажет «Небезопасное соединение» — это нормально для нашей лабораторки. Нажми «Дополнительно» → «Перейти на сайт»
3. Вставь токен из лога (`vagrant up` вывел его в конце — ищи строку `ТОКЕН ДЛЯ ВХОДА`)
4. Если токен не сохранился — получи новый:
   ```powershell
   vagrant ssh k8s-master -- kubectl -n kubernetes-dashboard create token admin-user --duration=24h
   ```

---

## Управление кластером

```powershell
vagrant status              # посмотреть состояние ВМ (running/poweroff)
vagrant ssh k8s-master      # зайти на мастер (терминал Linux внутри ВМ)
vagrant halt                # выключить ВМ (данные сохраняются)
vagrant up                  # включить обратно
vagrant reload              # перезагрузить ВМ
vagrant destroy -f          # УДАЛИТЬ всё (ВМ и данные кластера)
```

---

## Что потыкать внутри кластера

Зайди на мастер: `vagrant ssh k8s-master`

```bash
# Смотреть ноды
kubectl get nodes -o wide

# Смотреть все Pod-ы
kubectl get pods --all-namespaces

# Запустить тестовое приложение
kubectl create deployment hello --image=nginx --replicas=3
kubectl get pods

# Посмотреть что происходит в реальном времени
kubectl get pods -w

# Удалить тестовое приложение
kubectl delete deployment hello
```

---

## Часто задаваемые вопросы

**Q: Ноды не переходят в Ready, висят в NotReady**
A: Calico может стартовать 3–5 минут. Подожди и проверь снова:
```powershell
vagrant ssh k8s-master -- kubectl get pods -n calico-system
```

**Q: vagrant up падает с ошибкой про порт**
A: Какой-то порт (2232, 2242, 2252, 6443, 30443) уже занят. Найди кто занимает:
```powershell
netstat -ano | findstr :2232
```

**Q: Мало RAM, кластер тормозит**
A: В `Vagrantfile` уменьши `vb.memory = 1024` (минимум для воркеров) и `vb.memory = 2048` для мастера.

**Q: Как выключить и не потерять данные?**
A: `vagrant halt` — выключает ВМ, данные на диске сохраняются. `vagrant up` — включает обратно.

**Q: Как сбросить всё и начать заново?**
A:
```powershell
vagrant destroy -f
vagrant up
```

---

## Что изучить дальше

- `../docs/technologies.md` — как устроен Kubernetes, containerd, Calico
- `../docs/references.md` — книги и ссылки для углублённого изучения
- `../stage2/` — Stage 2 с SSH-ключами и NSIS-визардом

---

## Конфигурация кластера (для справки)

| Параметр | Значение |
|----------|---------|
| Образ ОС | Ubuntu 24.04 LTS (bento/ubuntu-24.04) |
| Kubernetes | v1.34.6 |
| Container Runtime | containerd 1.7.x |
| CNI | Calico v3.28.0 (VXLAN) |
| Pod CIDR | 10.244.0.0/16 |
| Service CIDR | 10.96.0.0/12 |
| Master IP | 192.168.56.10 |
| Worker 1 IP | 192.168.56.11 |
| Worker 2 IP | 192.168.56.12 |
| Пользователь | vagrant / vagrant |
