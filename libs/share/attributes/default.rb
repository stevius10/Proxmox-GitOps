include_attribute 'config::default'

default['share']['user'] =
  100000    # (/etc/fstab) uid=..

default['share']['group'] =
  'root'    # (/etc/fstab) gid=..

default['share']['mount'] = [
  '/share'  # (container.local.env) MOUNT="/mnt/..:/share/.."
]
