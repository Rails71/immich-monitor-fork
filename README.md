# immich-monitor
Helper script that aids with `immich` container suspend and resume.

Currently `immich` likes to keep my NAS disks awake by using `postgres` to synchronize different processes.

The following `*.sh` is meant to be used to auto-start at boot, and then it will opportunistically suspend the associated containers after an idle period. It will then monitor for incoming `TCP` port `2283` connections to resume operation.

If everything is working, you should see messages such as:

```
Omar@NAS:/docker/immich-app$ dmesg | grep immich
[  121.159874] immich-monitor: [INFO] immich containers: looker
[  523.072802] immich-monitor: [INFO] immich containers: freeze
[  964.296959] immich-monitor: [INFO] immich containers: resume
```

## Configuration and install
### Nightly tasks and backups
To ensure immich is not paused for important background tasks synchronise the following variables with your nightly tasks
http(s)://immich.URL/admin/system-settings?isOpen=nightly-tasks
http(s)://immich.URL/admin/system-settings?isOpen=backup

e.g. for nightly tasks run at 0010 and database dumps at 0200, unpause the container for 20mins just beforehand
```
SCHEDULED_STARTS=("00:05" "0155")
SCHEDULED_DURATIONS=(1200 1200)
```
### Optional optimisations
To reduce unnessecary stop/start set a cooldown time e.g.
```
COOLDOWN_AFTER_UNPAUSE=300 # wait 5mins before pausing again
```
For most home lab users reducing the checkinterval to 1s will not hurt performance
```
CHECK_INTERVAL=1
```

### Running the script as a service
#### 1. Install script
```
sudo cp immich-monitor.sh /usr/local/bin/immich-monitor.sh
sudo chmod +x /usr/local/bin/immich-monitor.sh
```
#### 2. Create service user and docker config directory
The empty directory prevents Docker from trying to read a per‑user config file, keeping the logs clean
```
sudo useradd --system --no-create-home --shell /sbin/nologin immichmonitor
sudo usermod -aG docker immichmonitor
sudo mkdir -p /var/lib/immichmonitor-docker
sudo chown immichmonitor:docker /var/lib/immichmonitor-docker
```
#### 3. Install systemd service
```
sudo cp immich-monitor.service /etc/systemd/system/immich-monitor.service
```
#### 4. Enable + start
```
sudo systemctl daemon-reload
sudo systemctl enable immich-monitor.service
sudo systemctl start immich-monitor.service
```
#### 5. Check status + logs
```
sudo systemctl status immich-monitor.service
journalctl -u immich-monitor.service -f
```
#### uninstall
```
# Stop and disable the service
sudo systemctl stop immich-monitor.service
sudo systemctl disable immich-monitor.service

# Remove service file
sudo rm /etc/systemd/system/immich-monitor.service
sudo systemctl daemon-reload

# Remove script
sudo rm /usr/local/bin/immich-monitor.sh

# Remove Docker config directory
sudo rm -rf /var/lib/immichmonitor-docker

# Remove service user
sudo userdel immichmonitor
```
