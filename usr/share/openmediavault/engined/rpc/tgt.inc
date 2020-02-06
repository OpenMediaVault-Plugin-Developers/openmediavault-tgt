 <?php

/**
 * Copyright (C) 2019 OpenMediaVault Plugin Developers
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
        return "tgt";
    }

    public function initialize()
    {
        $this->registerMethod("getSettings");
        $this->registerMethod("setSettings");
        $this->registerMethod("getTargetList");
        $this->registerMethod("setTarget");
        $this->registerMethod("getTarget");
        $this->registerMethod("deleteTarget");
    }

    public function getSettings($params, $context)
    {
        // Validate the RPC caller context.
        $this->validateMethodContext($context, ["role" => OMV_ROLE_ADMINISTRATOR]);
        // Get configuration object
        $db = \OMV\Config\Database::getInstance();
        $object = $db->get("conf.service.tgt");
        // Remove useless properties from the object.
        $object->remove("targets");
        return $object->getAssoc();
    }

    public function setSettings($params, $context)
    {
        // Validate the RPC caller context.
        $this->validateMethodContext($context, ["role" => OMV_ROLE_ADMINISTRATOR]);
        // Validate the parameters of the RPC service method.
        $this->validateMethodParams($params, "rpc.tgt.setsettings");
        // Get the existing configuration object.
        $db = \OMV\Config\Database::getInstance();
        $object = $db->get("conf.service.tgt");
        $object->setAssoc($params);
        // Set the configuration object.
        $db->set($object);
        // Remove useless properties from the object.
        $object->remove("targets");
        // Return the configuration object.
        return $object->getAssoc();
    }

     public function getTargetList($params, $context)
     {
        // Validate the RPC caller context.
        $this->validateMethodContext($context, ["role" => OMV_ROLE_ADMINISTRATOR]);
        // Validate the parameters of the RPC service method.
        $this->validateMethodParams($params, "rpc.common.getlist");
        // Get the configuration object.
        $db = \OMV\Config\Database::getInstance();
        $objects = $db->getAssoc("conf.service.tgt.target");
        // Filter the result.
        return $this->applyFilter($objects,$params['start'],$params['limit'],
            $params['sortfield'],$params['sortdir']);
    }

    public function getTarget($params, $context)
    {
        // Validate the RPC caller context.
        $this->validateMethodContext($context, ["role" => OMV_ROLE_ADMINISTRATOR]);
        // Validate the parameters of the RPC service method.
        $this->validateMethodParams($params, "rpc.common.objectuuid");
        // Get the configuration object.
        $db = \OMV\Config\Database::getInstance();
        return $db->getAssoc("conf.service.tgt.target", $params['uuid']);
    }

    public function setTarget($params, $context)
    {
        // Validate the RPC caller context.
        $this->validateMethodContext($context, ["role" => OMV_ROLE_ADMINISTRATOR]);
        // Validate the parameters of the RPC service method.
        $this->validateMethodParams($params, "rpc.tgt.settarget");
        // Replace comma or multiple spaces with one space
        $params["initiatoraddress"] = trim($params["initiatoraddress"]);
        $params["initiatoraddress"] = str_replace(",", " ", $params["initiatoraddress"]);
        $params["initiatoraddress"] = preg_replace("/\s+/", " ", $params["initiatoraddress"]);
        // Prepare the configuration object.
        $object = new \OMV\Config\ConfigObject("conf.service.tgt.target");
        $object->setAssoc($params);
        // Set the configuration object.
        $db = \OMV\Config\Database::getInstance();
        if (TRUE === $object->isNew()) {
            // Check uniqueness:
            $db->assertIsUnique($object, "uuid");
            $db->assertIsUnique($object, "name");
            // naming rule : [ iqn.(year)-(month).(reverse of domain name):(any name you like) ]
            $hostname = gethostbyaddr(gethostbyname(gethostname()));
            $hn2 = implode('.',array_reverse(explode('.',$hostname)));
            $iqn = sprintf('iqn.%d-%d.%s:%s',date('Y'),date('m'),$hn2,$params['name']);
            $object->set('iqn', $iqn);
        }
        $db->set($object);
        // Return the configuration object.
        return $object->getAssoc();
    }

    public function deleteTarget($params, $context)
    {
        // Validate the RPC caller context.
        $this->validateMethodContext($context, ["role" => OMV_ROLE_ADMINISTRATOR]);
        // Validate the parameters of the RPC service method.
        $this->validateMethodParams($params, "rpc.common.objectuuid");
        // Delete the configuration object.
        $db = \OMV\Config\Database::getInstance();
        $object = $db->get("conf.service.tgt.target", $params['uuid']);
        $db->delete($object);
        // Return the deleted configuration object.
        return $object->getAssoc();
    }
}
