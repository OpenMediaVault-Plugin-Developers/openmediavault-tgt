/**
 * @license   http://www.gnu.org/licenses/gpl.html GPL Version 3
 * @author    OpenMediaVault Plugin Developers <plugins@omv-extras.org>
 * @copyright Copyright (c) 2019-2020 OpenMediaVault Plugin Developers
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <http://www.gnu.org/licenses/>.
 */
// require("js/omv/WorkspaceManager.js")
// require("js/omv/workspace/grid/Panel.js")
// require("js/omv/workspace/window/Form.js")
// require("js/omv/workspace/window/plugin/ConfigObject.js")
// require("js/omv/Rpc.js")
// require("js/omv/data/Store.js")
// require("js/omv/data/Model.js")
// require("js/omv/data/proxy/Rpc.js")

Ext.define("OMV.module.admin.service.tgt.Target", {
    extend: "OMV.workspace.window.Form",
    requires: [
        "OMV.workspace.window.plugin.ConfigObject"
    ],

    rpcService: "Tgt",
    rpcGetMethod: "getTarget",
    rpcSetMethod: "setTarget",
    plugins: [{
        ptype: "configobject"
    }],

    getFormItems: function() {
        var me = this;
        return [{
            xtype: "checkbox",
            name: "enable",
            fieldLabel: _("Enable"),
            checked: true
        },{
            xtype: "textfield",
            name: "name",
            fieldLabel: _("Name"),
            allowBlank: false
        },{
            xtype: "textfield",
            name: "iqn",
            fieldLabel: _("Name"),
            readOnly: true,
            hidden: true
        },{
            xtype: "textfield",
            name: "backingstore",
            fieldLabel: _("Backing Store"),
            allowBlank: false
        },{
            xtype: "textfield",
            name: "initiatoraddress",
            fieldLabel: _("Initiator Address"),
            allowBlank: true,
            plugins: [{
                ptype: "fieldinfo",
                text: _("Multiple addresses can be entered with a space between each entry.") +
                        "<br />" +
                      _("Hostname or IP address can be used.") +
                        "<br />" +
                      _("Field can be left blank to allow any to access.")
            }]
        },{
            xtype: "textarea",
            name: "extraoptions",
            fieldLabel: _("Extra options"),
            allowBlank: true
        }];
    }
});

Ext.define("OMV.module.admin.service.tgt.Targets", {
    extend: "OMV.workspace.grid.Panel",
    requires: [
        "OMV.Rpc",
        "OMV.data.Store",
        "OMV.data.Model",
        "OMV.data.proxy.Rpc"
    ],
    uses: [
        "OMV.module.admin.service.tgt.Target"
    ],

    hidePagingToolbar: false,
    stateful: true,
    stateId: "54f36842-191c-11ea-a1fc-df0f8dde6ae1",
    columns: [{
        xtype: "booleaniconcolumn",
        text: _("Enabled"),
        sortable: true,
        dataIndex: "enable",
        stateId: "enable",
        align: "center",
        width: 80,
        resizable: false,
        iconCls:  Ext.baseCSSPrefix + "grid-cell-booleaniconcolumn-switch"
    },{
        text: _("Name"),
        sortable: true,
        dataIndex: "name",
        stateId: "name"
    },{
        text: _("IQN"),
        sortable: true,
        dataIndex: "iqn",
        stateId: "iqn"
    },{
        text: _("Backing Store"),
        sortable: false,
        dataIndex: "backingstore",
        stateId: "backingstore"
    },{
        text: _("Initiator Address"),
        sortable: false,
        dataIndex: "initiatoraddress",
        stateId: "initiatoraddress",
        renderer: function(value) {
            var newval = value.replace(/ /g, "<br />");
            var template = Ext.create('Ext.XTemplate', '<tpl for=".">{.}<br/></tpl>');
            return template.apply(newval);
        }
    }],

    initComponent: function() {
        var me = this;
        Ext.apply(me, {
            store: Ext.create("OMV.data.Store", {
                autoLoad: true,
                model: OMV.data.Model.createImplicit({
                    idProperty: "uuid",
                    fields: [
                        { name: "uuid", type: "string" },
                        { name: "enable", type: "boolean" },
                        { name: "name", type: "string" },
                        { name: "iqn", type: "string" },
                        { name: "backingstore", type: "string" },
                        { name: "initiatoraddress", type: "string" }
                    ]
                }),
                proxy: {
                    type: "rpc",
                    rpcData: {
                        service: "Tgt",
                        method: "getTargetList"
                    }
                },
                remoteSort: true,
                sorters: [{
                    direction: "ASC",
                    property: "name"
                }]
            })
        });
        me.callParent(arguments);
    },

    onAddButton: function() {
        var me = this;
        Ext.create("OMV.module.admin.service.tgt.Target", {
            title: _("Add Target"),
            uuid: OMV.UUID_UNDEFINED,
            listeners: {
                scope: me,
                submit: function() {
                    this.doReload();
                }
            }
        }).show();
    },

    onEditButton: function() {
        var me = this;
        var record = me.getSelected();
        Ext.create("OMV.module.admin.service.tgt.Target", {
            title: _("Edit Target"),
            uuid: record.get("uuid"),
            listeners: {
                scope: me,
                submit: function() {
                    this.doReload();
                }
            }
        }).show();
    },

    doDeletion: function(record) {
        var me = this;
        OMV.Rpc.request({
            scope: me,
            callback: me.onDeletion,
            rpcData: {
                service: "Tgt",
                method: "deleteTarget",
                params: {
                    uuid: record.get("uuid")
                }
            }
        });
    }
});

OMV.WorkspaceManager.registerPanel({
    id: "targets",
    path: "/service/tgt",
    text: _("Targets"),
    position: 20,
    className: "OMV.module.admin.service.tgt.Targets"
});
