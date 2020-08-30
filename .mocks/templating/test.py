from jinja2 import Environment, FileSystemLoader
import yaml


file_loader = FileSystemLoader('roles')
env = Environment(loader=file_loader)

with open('roles/dock-swag/files/docker-compose.yml') as f:

    parent = yaml.load(f, Loader=yaml.FullLoader)

template = env.get_template('defaults/common_compose.yml.j2')

output = template.render(parent=parent, main_uid=1000, main_gid=1000)
print(output)
