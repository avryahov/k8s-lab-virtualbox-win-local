# Список литературы и источников

> **Обязательно** прочитать исходную документацию — это профессиональный стандарт.
> Ссылки ниже — официальные источники и проверенные книги.
> Перед тем как задать вопрос «почему это не работает» — открой соответствующий раздел.

---

## 1. Kubernetes

### Официальная документация (обязательно)

| Ресурс | Описание |
|--------|----------|
| https://kubernetes.io/docs/concepts/ | Основные концепции (Pod, Service, Deployment...) |
| https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/ | Установка через kubeadm — то, что делает наш lab |
| https://kubernetes.io/docs/reference/kubectl/ | Справочник kubectl-команд |
| https://kubernetes.io/docs/concepts/workloads/pods/ | Что такое Pod |
| https://kubernetes.io/docs/concepts/services-networking/service/ | Что такое Service |
| https://kubernetes.io/docs/reference/access-authn-authz/rbac/ | Ролевая модель доступа (RBAC) |

### Книги на английском

| Книга | Автор | Издание | Уровень | Что охватывает |
|-------|-------|---------|---------|----------------|
| **Kubernetes in Action** | Marko Luksa | Manning, 2nd ed. 2024 | Средний → Продвинутый | Лучшая книга по K8s: глубоко, с практикой. Гл. 1–4 — для начинающих, гл. 11 — сеть |
| **The Kubernetes Book** | Nigel Poulton | 2024 ed. | Начальный | Быстрый старт, понятные объяснения без воды |
| **Programming Kubernetes** | Michael Hausenblas, Stefan Schimanski | O'Reilly, 2019 | Продвинутый | Разработка операторов и CRD |
| **Kubernetes: Up and Running** | Brendan Burns, Joe Beda, Kelsey Hightower | O'Reilly, 3rd ed. 2022 | Начальный → Средний | Авторы — создатели K8s в Google |
| **Kubernetes Patterns** | Bilgin Ibryam, Roland Huß | O'Reilly, 2nd ed. 2023 | Средний | Паттерны проектирования для K8s-приложений |

### Книги на русском

| Книга | Автор | Издательство | Уровень |
|-------|-------|--------------|---------|
| **Kubernetes в действии** | Марко Лукша | ДМК Пресс, 2019 | Средний → Продвинутый |
| **Kubernetes для разработчиков** | Джозеф Санингер | ДМК Пресс, 2020 | Начальный → Средний |

### Курсы и интерактивные ресурсы

| Ресурс | Тип | Язык |
|--------|-----|------|
| https://kubernetes.io/docs/tutorials/kubernetes-basics/ | Интерактивный туториал | EN |
| https://killercoda.com/kubernetes | Браузерные сценарии (бесплатно) | EN |
| https://www.cncf.io/certification/ckad/ | CKAD — сертификация разработчика | EN |
| https://www.cncf.io/certification/cka/ | CKA — сертификация администратора | EN |

---

## 2. VirtualBox

### Официальная документация

| Ресурс | Описание |
|--------|----------|
| https://www.virtualbox.org/manual/ | Полное руководство пользователя |
| https://www.virtualbox.org/manual/ch06.html | Сетевые адаптеры: NAT, Host-only, Bridge |
| https://www.virtualbox.org/manual/ch04.html | Guest Additions (совместные папки) |

### Книги

| Книга | Автор | Издание |
|-------|-------|---------|
| **Mastering VirtualBox** | Mihail Brasoveanu | Packt, 2019 |

---

## 3. Vagrant

### Официальная документация (обязательно)

| Ресурс | Описание |
|--------|----------|
| https://developer.hashicorp.com/vagrant/docs | Главная документация Vagrant |
| https://developer.hashicorp.com/vagrant/docs/vagrantfile | Справочник Vagrantfile |
| https://developer.hashicorp.com/vagrant/docs/provisioning/shell | Shell Provisioner |
| https://developer.hashicorp.com/vagrant/docs/networking | Сети в Vagrant |
| https://app.vagrantup.com/boxes/search | Каталог образов (boxes) |

### Книги

| Книга | Автор | Издание |
|-------|-------|---------|
| **Vagrant: Up and Running** | Mitchell Hashimoto | O'Reilly, 2013 (автор Vagrant) |
| **Vagrant Virtual Development Environment Cookbook** | Chad Thompson | Packt, 2015 |

---

## 4. Linux (Ubuntu)

### Темы, необходимые для понимания этого проекта

| Тема | Документация |
|------|-------------|
| systemd / systemctl | https://systemd.io/ |
| sysctl | `man sysctl`, https://www.kernel.org/doc/html/latest/admin-guide/sysctl/ |
| iptables / nftables | https://netfilter.org/documentation/ |
| cgroups v2 | https://www.kernel.org/doc/html/latest/admin-guide/cgroup-v2.html |
| /etc/fstab | `man fstab` |
| bash scripting | https://www.gnu.org/software/bash/manual/bash.html |
| apt package manager | https://wiki.debian.org/Apt |

### Книги

| Книга | Автор | Издание | Язык |
|-------|-------|---------|------|
| **The Linux Command Line** | William Shotts | No Starch Press, 2nd ed. 2019 | EN |
| **Linux Command Line and Shell Scripting Bible** | Richard Blum | Wiley, 4th ed. 2021 | EN |
| **Командная строка Linux** | Уильям Шоттс | БХВ-Петербург | RU |
| **Unix и Linux: руководство системного администратора** | Эви Немет и др. | Вильямс | RU |

---

## 5. Контейнеры и containerd

### Официальная документация

| Ресурс | Описание |
|--------|----------|
| https://containerd.io/docs/ | containerd — документация |
| https://github.com/opencontainers/runc | runc — реализация OCI Container Runtime |
| https://opencontainers.org/ | Open Container Initiative (стандарты) |
| https://kubernetes.io/docs/setup/production-environment/container-runtimes/ | K8s и Container Runtime |

### Что такое CRI (Container Runtime Interface)

> CRI — интерфейс между kubelet и container runtime. Позволяет K8s работать
> с любым совместимым runtime: containerd, CRI-O, Docker (через dockershim — удалён в K8s 1.24).
>
> containerd ← kubelet (через CRI) ← kube-apiserver ← kubectl

### Книги

| Книга | Автор | Издание |
|-------|-------|---------|
| **Container Security** | Liz Rice | O'Reilly, 2020 |
| **Docker Deep Dive** | Nigel Poulton | 2023 ed. |
| **Docker в действии** | Джефф Николофф, Стивен Куэнзел | ДМК Пресс, 2020 |

---

## 6. Calico CNI

### Официальная документация (обязательно)

| Ресурс | Описание |
|--------|----------|
| https://docs.tigera.io/calico/latest/about/ | Что такое Calico |
| https://docs.tigera.io/calico/latest/getting-started/kubernetes/ | Установка на K8s |
| https://docs.tigera.io/calico/latest/networking/ipam/ | IP Address Management |
| https://docs.tigera.io/calico/latest/networking/vxlan-ipip | VXLAN vs IPIP |
| https://docs.tigera.io/calico/latest/network-policy/ | NetworkPolicy |

### Как работает VXLAN в Calico

> Каждая нода получает блок /26 из Pod CIDR (10.244.0.0/16).
> Трафик между Pod-ами на разных нодах оборачивается в UDP-пакет (порт 4789).
> Это «туннелирование» — VXLAN (Virtual Extensible LAN).
> Позволяет Pod-сети работать поверх любой физической сети.

---

## 7. Kubernetes Dashboard

### Официальная документация

| Ресурс | Описание |
|--------|----------|
| https://kubernetes.io/docs/tasks/access-application-cluster/web-ui-dashboard/ | Официальная документация |
| https://github.com/kubernetes/dashboard | Репозиторий GitHub |

---

## 8. SSH и криптография (для Stage 2)

### Официальная документация

| Ресурс | Описание |
|--------|----------|
| https://www.openssh.com/manual.html | OpenSSH Manual |
| `man ssh-keygen` | Генерация ключей |
| https://ed25519.cr.yp.to/ | Ed25519 — математика алгоритма |

### Почему Ed25519, а не RSA

> RSA 2048 бит: безопасность ~112 бит, медленный, ключ большой.
> Ed25519: безопасность ~128 бит (эквивалент RSA 3000+), быстрый, ключ 32 байта.
> Ed25519 рекомендован NIST, OpenSSH, GitHub, GitLab с 2014 года.
>
> Подробнее: https://blog.g3rt.nl/upgrade-your-ssh-keys.html

### Книги

| Книга | Автор | Издание |
|-------|-------|---------|
| **SSH: The Definitive Guide** | Daniel J. Barrett | O'Reilly, 2005 |
| **Cryptography and Network Security** | William Stallings | Pearson, 8th ed. 2022 |

---

## 9. Windows PowerShell и автоматизация

### Официальная документация

| Ресурс | Описание |
|--------|----------|
| https://learn.microsoft.com/en-us/powershell/scripting/ | PowerShell документация Microsoft |
| https://nsis.sourceforge.io/Docs/ | NSIS (Nullsoft Scriptable Install System) |
| https://learn.microsoft.com/en-us/windows/win32/secauthz/access-control-lists | Windows ACL |

---

## 10. Архитектура сетей

### Понимание сетевой модели Kubernetes

> Правило K8s: каждый Pod должен иметь возможность связаться с любым другим Pod-ом
> без NAT (прямой IP, без трансляции адресов).
>
> Это достигается CNI-плагинами: Calico, Cilium, Flannel, WeaveNet...

### Рекомендуемые статьи

| Ресурс | Тема |
|--------|------|
| https://kubernetes.io/docs/concepts/cluster-administration/networking/ | Модель сети K8s |
| https://learnk8s.io/kubernetes-network-packets | Как пакеты путешествуют в K8s |
| https://www.tigera.io/learn/guides/kubernetes-networking/ | Calico: сетевой гайд |

---

## Обязательный минимум для понимания этого проекта

Если ты только начинаешь — прочитай в таком порядке:

1. [The Kubernetes Book (Poulton)](https://nigelpoulton.com/books/) — краткое введение (несколько часов)
2. [kubernetes.io/docs/tutorials/kubernetes-basics/](https://kubernetes.io/docs/tutorials/kubernetes-basics/) — интерактивный туториал (30 минут)
3. [Kubernetes in Action (Luksa), гл. 1–4](https://www.manning.com/books/kubernetes-in-action-second-edition) — погружение в детали
4. [Vagrant: Up and Running (Hashimoto)](https://www.oreilly.com/library/view/vagrant-up-and/9781449336103/) — понять Vagrantfile
5. [Linux Command Line (Shotts)](https://linuxcommand.org/tlcl.php) — если bash незнаком (бесплатно онлайн)
