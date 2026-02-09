include_attribute 'config::default'

default['share']['group'] =
  'root'    # (/etc/fstab) gid=..

default['share']['mount'] = [
  '/share'  # (container.local.env) MOUNT="/mnt/..:/share/.."
]
