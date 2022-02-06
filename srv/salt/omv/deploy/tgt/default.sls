# @license   http://www.gnu.org/licenses/gpl.html GPL Version 3
# @author    OpenMediaVault Plugin Developers <plugins@omv-extras.org>
# @copyright Copyright (c) 2019-2022 OpenMediaVault Plugin Developers
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <http://www.gnu.org/licenses/>.

{% set config = salt['omv_conf.get']('conf.service.tgt') %}
{% set script_prefix = salt['pillar.get']('default:OMV_TGT_TARGET_PREFIX', 'openmediavault-') %}
{% set scripts_dir = '/etc/tgt/conf.d' %}

{% if config.enable | to_bool %}

configure_tgt:
  file.managed:
    - name: "/etc/tgt/targets.conf"
    - source:
      - salt://{{ tpldir }}/files/etc-tgt-targets_conf.j2
    - template: jinja
    - context:
        config: {{ config | json }}
    - user: root
    - group: root
    - mode: 644

remove_target_conf_files:
  module.run:
    - file.find:
      - path: "{{ scripts_dir }}"
      - iname: "{{ script_prefix }}*"
      - delete: "f"

{% for target in config.targets.target | selectattr('enable') %}

configure_tgt_target_{{ target.uuid }}:
  file.managed:
    - name: "{{ scripts_dir | path_join(script_prefix ~ target.uuid) }}.conf"
    - source:
      - salt://{{ tpldir }}/files/etc-tgt-conf_d-target_conf.j2
    - context:
        target: {{ target | json }}
    - template: jinja
    - user: root
    - group: root
    - mode: 644

{% endfor %}

start_tgt_service:
  service.running:
    - name: tgt
    - enable: True
    - watch:
      - file: configure_tgt*

{% else %}

stop_tgt_service:
  service.dead:
    - name: tgt
    - enable: False

{% endif %}
