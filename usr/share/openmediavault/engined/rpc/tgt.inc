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

class OMVRpcServiceTgt extends \OMV\Rpc\ServiceAbstract
{
    public function getName()
    {
        return 'tgt';
    }

    public function initialize()
    {
        $this->registerMethod('getSettings');
        $this->registerMethod('setSettings');

        $this->registerMethod('getTargetList');
        $this->registerMethod('setTarget');
        $this->registerMethod('getTarget');
        $this->registerMethod('deleteTarget');

        $this->registerMethod('getImageList');
        $this->registerMethod('setImage');
        $this->registerMethod('getImage');
        $this->registerMethod('deleteImage');
        $this->registerMethod('growImage');
    }

    public function getSettings($params, $context)
    {
        // Validate the RPC caller context.
        $this->validateMethodContext($context, ['role' => OMV_ROLE_ADMINISTRATOR]);
        // Get configuration object
        $db = \OMV\Config\Database::getInstance();
        $object = $db->get('conf.service.tgt');
        // Remove useless properties from the object.
        $object->remove('targets');
        return $object->getAssoc();
    }

    public function setSettings($params, $context)
    {
        // Validate the RPC caller context.
        $this->validateMethodContext($context, ['role' => OMV_ROLE_ADMINISTRATOR]);
        // Validate the parameters of the RPC service method.
        $this->validateMethodParams($params, 'rpc.tgt.setsettings');
        // Get the existing configuration object.
        $db = \OMV\Config\Database::getInstance();
        $object = $db->get('conf.service.tgt');
        $object->setAssoc($params);
        // Set the configuration object.
        $db->set($object);
        // Remove useless properties from the object.
        $object->remove('targets');
        // Return the configuration object.
        return $object->getAssoc();
    }

    public function getTargetList($params, $context)
    {
        // Validate the RPC caller context.
        $this->validateMethodContext($context, ['role' => OMV_ROLE_ADMINISTRATOR]);
        // Validate the parameters of the RPC service method.
        $this->validateMethodParams($params, 'rpc.common.getlist');
        // Get the configuration object.
        $db = \OMV\Config\Database::getInstance();
        $objects = $db->get('conf.service.tgt.target');
        // Add additional informations.
        $objectsAssoc = [];
        foreach ($objects as $objectk => &$objectv) {
            $objectv->add('initiators', 'string', str_replace(' ', '<br/>', $objectv->get('initiatoraddress')));
            $objectv->add('backingstores', 'string', str_replace(',', '<br/>', $objectv->get('backingstore')));
            $objectsAssoc[] = $objectv->getAssoc();
        }
        // Filter the result.
        return $this->applyFilter($objectsAssoc, $params['start'], $params['limit'],
            $params['sortfield'], $params['sortdir']);
    }

    public function getTarget($params, $context)
    {
        // Validate the RPC caller context.
        $this->validateMethodContext($context, ['role' => OMV_ROLE_ADMINISTRATOR]);
        // Validate the parameters of the RPC service method.
        $this->validateMethodParams($params, 'rpc.common.objectuuid');
        // Get the configuration object.
        $db = \OMV\Config\Database::getInstance();
        return $db->getAssoc('conf.service.tgt.target', $params['uuid']);
    }

    public function setTarget($params, $context)
    {
        // Validate the RPC caller context.
        $this->validateMethodContext($context, ['role' => OMV_ROLE_ADMINISTRATOR]);
        // Validate the parameters of the RPC service method.
        $this->validateMethodParams($params, 'rpc.tgt.settarget');
        // Replace comma or multiple spaces with one space
        $params['initiatoraddress'] = trim($params['initiatoraddress']);
        $params['initiatoraddress'] = str_replace(',', ' ', $params['initiatoraddress']);
        $params['initiatoraddress'] = preg_replace('/\s+/', ' ', $params['initiatoraddress']);
        // make sure delimiter is comma, unique the list, and trim each entry
        $stores = str_replace([';',':'], ',', $params['backingstore']);
        $paths = explode(',', $stores);
        $pathsu = array_unique($paths);
        $pathst = array_map('trim', $pathsu);
        $params['backingstore'] = implode(',', $pathst);
        // Prepare the configuration object.
        $object = new \OMV\Config\ConfigObject('conf.service.tgt.target');
        $object->setAssoc($params);
        // Set the configuration object.
        $db = \OMV\Config\Database::getInstance();
        if (TRUE === $object->isNew()) {
            // Check uniqueness:
            $db->assertIsUnique($object, 'uuid');
            $db->assertIsUnique($object, 'name');
            // naming rule : [ iqn.(year)-(month).(reverse of domain name):(any name you like) ]
            $output = [];
            $cmd = new \OMV\System\Process('hostname', '--fqdn');
            $cmd->execute($output);
            $hostname = $output[0];
            $hn2 = implode('.', array_reverse(explode('.', $hostname)));
            $iqn = sprintf('iqn.%s-%s.%s:%s',date('Y'),date('m'), $hn2, strtolower($params['name']));
            $object->set('iqn', $iqn);
        }
        if (empty($object->get('iqn'))) {
            throw new \OMV\Exception(gettext("iqn not set"));
        }
        $db->set($object);
        // Return the configuration object.
        return $object->getAssoc();
    }

    public function deleteTarget($params, $context)
    {
        // Validate the RPC caller context.
        $this->validateMethodContext($context, ['role' => OMV_ROLE_ADMINISTRATOR]);
        // Validate the parameters of the RPC service method.
        $this->validateMethodParams($params, 'rpc.common.objectuuid');
        // Delete the configuration object.
        $db = \OMV\Config\Database::getInstance();
        $object = $db->get('conf.service.tgt.target', $params['uuid']);
        $db->delete($object);
        // Return the deleted configuration object.
        return $object->getAssoc();
    }

    public function getImageList($params, $context)
    {
        // Validate the RPC caller context.
        $this->validateMethodContext($context, ['role' => OMV_ROLE_ADMINISTRATOR]);
        // Validate the parameters of the RPC service method.
        $this->validateMethodParams($params, 'rpc.common.getlist');
        // Get the configuration object.
        $db = \OMV\Config\Database::getInstance();
        $objects = $db->get('conf.service.tgt.image');
        // Add additional image information
        $objectsAssoc = [];
        foreach ($objects as $objectk => &$objectv) {
            // Add the new property 'imagesize'.
            $objectv->add('imagesize', 'string', '-1');
            $path = $objectv->get('path');
            if (file_exists($path)) {
                // Update the 'imagesize' property.
                $imagesize = '-1';
                if (PHP_INT_SIZE == 8) {
                    $imagesize = strval(filesize($path));
                } else {
                    $output = [];
                    $cmd = new \OMV\System\Process('stat', '-c %s', escapeshellarg($path));
                    $cmd->execute($output);
                    $imagesize = trim($output[0]);
                }
                $objectv->set('imagesize', $imagesize);
            }
            $objectsAssoc[] = $objectv->getAssoc();
        }
        // Filter the result.
        return $this->applyFilter($objectsAssoc,$params['start'],$params['limit'],
            $params['sortfield'],$params['sortdir']);
    }

    public function getImage($params, $context)
    {
        // Validate the RPC caller context.
        $this->validateMethodContext($context, ['role' => OMV_ROLE_ADMINISTRATOR]);
        // Validate the parameters of the RPC service method.
        $this->validateMethodParams($params, 'rpc.common.objectuuid');
        // Get the configuration object.
        $db = \OMV\Config\Database::getInstance();
        return $db->getAssoc('conf.service.tgt.image', $params['uuid']);
    }

    public function setImage($params, $context)
    {
        // Validate the RPC caller context.
        $this->validateMethodContext($context, ['role' => OMV_ROLE_ADMINISTRATOR]);
        // Validate the parameters of the RPC service method.
        $this->validateMethodParams($params, 'rpc.tgt.setimage');
        $imagesize = $params['imagesize'];
        unset($params['imagesize']);
        // Prepare the configuration object.
        $object = new \OMV\Config\ConfigObject('conf.service.tgt.image');
        $object->setAssoc($params);
        // Set the configuration object.
        $db = \OMV\Config\Database::getInstance();
        if (TRUE === $object->isNew()) {
            // Check uniqueness:
            $db->assertIsUnique($object, 'path');
        }
        if (!file_exists($object->get('path'))) {
            $cmdArgs = [];
            $cmdArgs[] = 'if=/dev/zero';
            $cmdArgs[] = sprintf('of="%s"', $object->get('path'));
            $cmdArgs[] = 'bs=1';
            $cmdArgs[] = sprintf('seek=%dG', $imagesize);
            $cmdArgs[] = 'count=0';
            $cmd = new \OMV\System\Process('dd', $cmdArgs);
            $cmd->execute($output);
        } else {
            throw new \OMV\Exception(
                "Image already exists - '%s'.", $object->get('path')
            );
        }
        $db->set($object);
        // Return the configuration object.
        return $object->getAssoc();
    }

    public function deleteImage($params, $context)
    {
        // Validate the RPC caller context.
        $this->validateMethodContext($context, ['role' => OMV_ROLE_ADMINISTRATOR]);
        // Validate the parameters of the RPC service method.
        $this->validateMethodParams($params, 'rpc.common.objectuuid');
        // Delete the configuration object.
        $db = \OMV\Config\Database::getInstance();
        $object = $db->get('conf.service.tgt.image', $params['uuid']);
        $db->delete($object);
        // Delete the image file
        if (file_exists($object->get('path'))) {
            unlink($object->get('path'));
        }
        // Return the deleted configuration object.
        return $object->getAssoc();
    }

    public function growImage($params, $context)
    {
        // Validate the RPC caller context.
        $this->validateMethodContext($context, ['role' => OMV_ROLE_ADMINISTRATOR]);
        // Validate the parameters of the RPC service method.
        $this->validateMethodParams($params, 'rpc.tgt.growimage');
        // Get the configuration object.
        $db = \OMV\Config\Database::getInstance();
        $object = $db->get("conf.service.tgt.image", $params['uuid']);
        if (file_exists($object->get('path'))) {
            $cmdArgs = [];
            $cmdArgs[] = 'if=/dev/zero';
            $cmdArgs[] = sprintf('of="%s"', $object->get('path'));
            $cmdArgs[] = 'bs=1';
            $cmdArgs[] = sprintf('seek=%dG', $params['amount']);
            $cmdArgs[] = 'count=0';
            $cmd = new \OMV\System\Process('dd', $cmdArgs);
            $cmd->execute($output);
            file_put_contents("/tmp/test2", $output);
            file_put_contents("/tmp/test2", $cmd->getCommandLine(), FILE_APPEND);
        } else {
            throw new \OMV\Exception(
                "Image does not exist - '%s'.", $object->get('path')
            );
        }
    }
}
