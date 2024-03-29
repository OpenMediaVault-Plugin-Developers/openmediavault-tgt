<?php

/**
 * Copyright (C) 2019-2024 openmediavault plugin developers
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

class OMVModuleTgt extends \OMV\Engine\Module\ServiceAbstract
    implements \OMV\Engine\Notify\IListener, \OMV\Engine\Module\IServiceStatus
{
    public function getName()
    {
        return 'tgt';
    }

    public function getStatus()
    {
        $db = \OMV\Config\Database::getInstance();
        $object = $db->get('conf.service.tgt');
        $systemCtl = new \OMV\System\SystemCtl('tgt');
        return [
            'name' => $this->getName(),
            'title' => gettext("tgt"),
            'enabled' => $object->get('enable'),
            'running' => $systemCtl->isActive()
        ];
    }

    public function bindListeners(\OMV\Engine\Notify\Dispatcher $dispatcher)
    {
        $dispatcher->addListener(
            OMV_NOTIFY_MODIFY,
            'org.openmediavault.conf.service.tgt',
            [ $this, 'setDirty' ]
        );
        $dispatcher->addListener(
            OMV_NOTIFY_CREATE | OMV_NOTIFY_MODIFY | OMV_NOTIFY_DELETE,
            'org.openmediavault.conf.service.tgt.target',
            [ $this, 'setDirty' ]
        );
    }
}
