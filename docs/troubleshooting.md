# Устранение неисправностей

## Нода в статусе NotReady

```bash
# Проверить статус kubelet
systemctl status kubelet --no-pager
journalctl -u kubelet -n 50 --no-pager

# Проверить CNI
kubectl get pods -n kube-flannel
kubectl describe pod -n kube-flannel <pod-name>
```

Причина: kubelet зарегистрировал ноду с IP `10.0.2.15` (NAT-адаптер) вместо private IP.
Решение: проверить `/etc/default/kubelet` — должно содержать `KUBELET_EXTRA_ARGS=--node-ip=192.168.56.X`.

```bash
cat /etc/default/kubelet
# Если пусто или неверный IP — исправить и перезапустить:
sudo systemctl restart kubelet
```

---

## Worker не подключился к кластеру

```bash
# На worker — проверить логи
journalctl -u kubelet -n 30 --no-pager

# На master — проверить join-command
cat /vagrant/join-command.sh
```

Токен join-command живёт **24 часа**. Если кластер пересоздавался — перегенерировать:

```bash
# На master
kubeadm token create --print-join-command
```

---

## Ошибка при vagrant up: "Failed to generate SSH key"

PowerShell execution policy заблокировала скрипт.

```powershell
# Проверить текущую политику
Get-ExecutionPolicy

# Разрешить локальные скрипты
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

---

## Ошибка VirtualBox: "Cannot enable the audio adapter"

Не критично — кластеру аудио не нужно. Добавьте в `.env`:

```
# Уже настроено через vb.gui = false
```

Если ошибка блокирует запуск — обновите VirtualBox до актуальной версии 7.x.

---

## Порт уже занят (address already in use)

```
Vagrant cannot forward the specified ports on this VM: 2232, 6443 ...
```

Найти и освободить порт:

```powershell
netstat -ano | findstr :2232
# Найти PID → завершить процесс или изменить порт в .env
```

Или изменить в `.env`:
```
MASTER_SSH_PORT=2333
MASTER_API_PORT=6444
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

Если box повреждён:

```powershell
vagrant box list
vagrant box remove bento/ubuntu-22.04
vagrant up  # скачает box заново
```

---

## kubectl: connection refused

```bash
# Убедиться, что kubeconfig корректный
kubectl cluster-info

# Если используете kubeconfig с хоста — проверить адрес сервера
cat kubeconfig.yaml | grep server
# Должно быть 127.0.0.1:6443 (не 192.168.56.10:6443 при доступе с хоста)
```

---

## Flannel pods в состоянии CrashLoopBackOff

```bash
kubectl describe pod -n kube-flannel <pod-name>
# Смотреть Events и Logs

kubectl logs -n kube-flannel <pod-name>
```

Типичная причина: несоответствие `POD_CIDR` в `.env` и в манифесте Flannel.
Значение по умолчанию `10.244.0.0/16` совместимо с Flannel без изменений.

---

## Полный сброс и пересоздание

```powershell
vagrant destroy -f
Remove-Item -Recurse .vagrant\node-keys -ErrorAction SilentlyContinue
vagrant up
```
