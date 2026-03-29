# Быстрый старт: Stage 1 на Windows 11 Home

Этот документ описывает самый короткий и при этом правильный ручной запуск учебного `stage1`.

---

## Перед началом

Проверь, что установлены:

```powershell
vagrant --version
& "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe" --version
```

---

## Где запускать команды

Все команды ниже нужно выполнять именно из папки:

```powershell
cd K:\repositories\git\ipr\crm\stage1
```

Это важно:

- `Vagrantfile` для учебного сценария лежит именно в `stage1`;
- post-bootstrap скрипт тоже рассчитан на запуск из этой папки;
- так Vagrant не перепутает этот сценарий с другими частями проекта.

---

## Минимальный сценарий в 2 команды

```powershell
vagrant up
powershell -ExecutionPolicy Bypass -File .\scripts\run-post-bootstrap.ps1
```

Если хочется запустить всё одной командой и дальше только наблюдать за процессом, используй:

```powershell
.\launch.bat
```

Этот bat-файл последовательно выполнит:

- `vagrant up`
- post-bootstrap сценарий
- финальную краткую проверку нод

### Что делает первая команда

`vagrant up`:

1. создаёт 3 ВМ;
2. настраивает master и worker-ноды;
3. выполняет `kubeadm init`;
4. выполняет `kubeadm join` для двух worker-нод.

### Что делает вторая команда

`run-post-bootstrap.ps1`:

1. проверяет, что все 3 ноды появились в API;
2. завершает сетевую настройку кластера;
3. проверяет Calico;
4. применяет smoke-тест `nginx`;
5. ждёт успешного завершения smoke-теста;
6. только потом ставит Dashboard.

---

## Что проверять после запуска

### Проверка в терминале

```powershell
vagrant ssh k8s-master -c "sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl get nodes -o wide"
```

Ожидаемый результат:

- `k8s-master` — `Ready`
- `k8s-worker1` — `Ready`
- `k8s-worker2` — `Ready`

### Проверка Dashboard в браузере

Открой:

`https://localhost:30443`

Потом:

1. подтверди переход через предупреждение браузера;
2. вставь токен из вывода `run-post-bootstrap.ps1`;
3. открой `Nodes` и убедись, что там 3 ноды;
4. открой namespace `smoke-tests` и проверь:
   - `Deployment` `nginx-smoke`;
   - `Service` `nginx-smoke`;
   - `Job` `nginx-smoke-check`.

---

## Если токен Dashboard потерялся

```powershell
vagrant ssh k8s-master -c "sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl -n kubernetes-dashboard create token admin-user --duration=24h"
```

---

## Если нужно начать заново

```powershell
vagrant destroy -f
vagrant up
powershell -ExecutionPolicy Bypass -File .\scripts\run-post-bootstrap.ps1
```

После `destroy` сценарий должен очистить:

- локальный `.vagrant`;
- `join-command.sh`;
- токен экземпляра stage1;
- пул портов stage1;
- временные runtime-хвосты текущего учебного сценария.

---

## FAQ

### Почему `vagrant up` недостаточно?

Потому что учебный сценарий теперь разделён на 2 понятные части:

- сначала базовый bootstrap кластера;
- потом финальная проверка сети, smoke-тест и Dashboard.

Так ученик лучше понимает, где именно рождается кластер, а где идут дополнительные сервисы.

### Почему Dashboard ставится только в конце?

Потому что Dashboard не должен ломать базовый подъём кластера.
Сначала надо доказать, что работают master, worker-ы, сеть и простое приложение.

### Почему smoke-тест вынесен в отдельный манифест?

Чтобы его можно было повторять много раз и использовать как учебный эталон проверки кластера.

---

## Что читать дальше

- [Stage 1 README](K:\repositories\git\ipr\crm\stage1\README.md)
- [Архитектура](K:\repositories\git\ipr\crm\docs\architecture.md)
- [Устранение неисправностей](K:\repositories\git\ipr\crm\docs\troubleshooting.md)
