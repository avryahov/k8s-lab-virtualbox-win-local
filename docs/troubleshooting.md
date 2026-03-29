# Устранение неисправностей

> **Методология диагностики:** сначала `kubectl get pods -A`, потом `kubectl describe pod <имя>`,
> потом `kubectl logs <имя>`. 90% проблем видны в этих трёх командах.

---

## Нода в статусе NotReady

```bash
# На мастере — проверить ноды
kubectl get nodes -o wide

# Зайти на проблемную ноду и проверить kubelet
systemctl status kubelet --no-pager
journalctl -u kubelet -n 50 --no-pager
```

**Причина А — неверный NODE_IP:**
Kubelet зарегистрировал ноду с IP `10.0.2.15` (NAT-адаптер) вместо host-only IP.
Проверь:
```bash
cat /etc/default/kubelet
# Должно содержать: KUBELET_EXTRA_ARGS=--node-ip=192.168.56.X
```
Если пусто или неверный IP:
```bash
echo 'KUBELET_EXTRA_ARGS=--node-ip=192.168.56.10' | sudo tee /etc/default/kubelet
sudo systemctl daemon-reload && sudo systemctl restart kubelet
```

**Причина Б — Calico ещё не запустился:**
После `vagrant up` Calico стартует 2–5 минут. Подожди и проверь:
```bash
kubectl get pods -n calico-system -o wide
```
Все `calico-node-*` должны быть `1/1 Running`.

---

## Calico pods в CrashLoopBackOff

```bash
# Проверить какие именно pods упали
kubectl get pods -n calico-system -o wide

# Посмотреть логи
kubectl logs -n calico-system <pod-name> -c calico-node | tail -30

# Частая ошибка: "Typha discovery failed: Kubernetes service missing IP or port"
# Причина: cascading failure после перезапуска ВМ с DHCP-адресами
```

**Решение — перезапуск всех Calico pods:**
```bash
kubectl delete pods -n calico-system --all
# Подождать 60–90 секунд
kubectl get pods -n calico-system -w
# Все должны стать 1/1 Running
```

**Почему это помогает:**
После restart ВМ Typha pods могут стартовать раньше, чем их Service получит Endpoints.
calico-node видит пустой список Typha → падает. Полный рестарт выравнивает порядок.

---

## Worker не подключился к кластеру

```bash
# На воркере — логи
journalctl -u kubelet -n 30 --no-pager

# На мастере — проверить join-command
cat /vagrant/join-command.sh
```

Bootstrap-токен **живёт 24 часа**. Если пересоздавал ВМ или прошли сутки:
```bash
# На мастере — новый токен
kubeadm token create --print-join-command > /vagrant/join-command.sh
# На воркере
sudo bash /vagrant/join-command.sh
```

---

## Kubernetes Dashboard недоступен

**Где Dashboard:**

| Сценарий | URL |
|----------|-----|
| Vagrant (Stage 1/2) | `https://localhost:30443` |
| Реальный кластер (bridge-сеть) | `https://<IP-мастера>:30443` |
| Изнутри ВМ | `https://192.168.56.10:30443` |

**Браузер предупреждает о сертификате** — это нормально! Dashboard использует
самоподписанный TLS-сертификат. Нажми «Дополнительно» → «Перейти на сайт».

**Получить токен для входа:**
```bash
kubectl -n kubernetes-dashboard create token admin-user --duration=24h
```

**Dashboard Pod не запустился:**
```bash
kubectl get pods -n kubernetes-dashboard -o wide
kubectl logs -n kubernetes-dashboard <pod-name>
# Подожди 2–3 минуты — Pod стартует после Calico
```

**NodePort недоступен с хоста:**
```bash
# Проверить что сервис существует
kubectl get svc -n kubernetes-dashboard

# Проверить открытость порта
curl -k -v https://localhost:30443
# Или напрямую к IP мастера
curl -k -v https://192.168.56.10:30443
```

**ВАЖНО: dashboard работает только по HTTPS, не HTTP!**
`http://localhost:30443` → ошибка соединения (это правильное поведение).
`https://localhost:30443` → страница входа Dashboard.

---

## Ошибка при vagrant up: "Failed to generate SSH key"

PowerShell execution policy заблокировала скрипт. (Только для Stage 2, не для Stage 1.)

```powershell
# Проверить текущую политику
Get-ExecutionPolicy

# Разрешить локальные скрипты
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

---

## Порт уже занят (address already in use)

```
Vagrant cannot forward the specified ports on this VM: 2232, 6443 ...
```

Найти что занимает порт:
```powershell
netstat -ano | findstr :2232
# Найти PID и завершить процесс, или изменить порт в .env (Stage 2)
```

Для Stage 1 — поменяй в `stage1/Vagrantfile`:
```ruby
master.vm.network "forwarded_port", guest: 22, host: 2233, id: "ssh-master"
```

---

## Кластер завис во время provisioning

```powershell
# Остановить всё
vagrant halt

# Уничтожить и начать заново
vagrant destroy -f
vagrant up
```

Если box повреждён (ошибка при скачивании):
```powershell
vagrant box list
vagrant box remove bento/ubuntu-24.04
vagrant up  # скачает box заново
```

---

## kubectl: connection refused (с хоста Windows)

При работе с kubectl с хоста Windows нужен kubeconfig с адресом `127.0.0.1:6443`.

```powershell
# Скопировать kubeconfig с мастера
vagrant ssh k8s-master --command "cat /home/vagrant/.kube/config" > kubeconfig.yaml

# Заменить server IP: 192.168.56.10:6443 → 127.0.0.1:6443
(Get-Content kubeconfig.yaml) -replace "192.168.56.10", "127.0.0.1" | Set-Content kubeconfig.yaml

# Использовать
$env:KUBECONFIG = "$(pwd)\kubeconfig.yaml"
kubectl get nodes
```

---

## CoreDNS в CrashLoopBackOff

Обычно CoreDNS падает из-за:
1. Нехватки памяти на ноде (OOM) — добавь RAM в `.env` или `Vagrantfile`
2. Сетевых проблем на ноде, где запущен Pod

```bash
kubectl logs -n kube-system <coredns-pod-name> --previous
kubectl get events -n kube-system --sort-by=.lastTimestamp

# Если причина OOM:
kubectl describe node k8s-worker2 | grep -A5 "Conditions:"
```

Для Vagrant — убедись, что `vb.memory >= 2048` в Vagrantfile.

---

## Полный сброс и пересоздание

**Stage 1:**
```powershell
cd stage1
vagrant destroy -f
vagrant up
```

**Stage 2:**
```powershell
vagrant destroy -f
Remove-Item -Recurse .vagrant\node-keys -ErrorAction SilentlyContinue
vagrant up
```

---

## Быстрая диагностика одной командой

```bash
# Запустить на мастере — показывает всё что не так
kubectl get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded 2>/dev/null
kubectl get nodes -o wide
```
