/**
 * @license   http://www.gnu.org/licenses/gpl.html GPL Version 3
 * @author    OpenMediaVault Plugin Developers <plugins@omv-extras.org>
 * @copyright Copyright (c) 2020 OpenMediaVault Plugin Developers
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
// require("js/omv/module/admin/service/tgt/util/Format.js")

Ext.define("OMV.module.admin.service.tgt.Image", {
    extend: "OMV.workspace.window.Form",
    requires: [
        "OMV.workspace.window.plugin.ConfigObject"
    ],

    height: 210,

    rpcService: "Tgt",
    rpcGetMethod: "getImage",
    rpcSetMethod: "setImage",
    plugins: [{
        ptype: "configobject"
    }],

    getFormItems: function() {
        var me = this;
        return [{
            xtype: "textfield",
            name: "path",
            fieldLabel: _("Path"),
            allowBlank: false,
            plugins: [{
                ptype: "fieldinfo",
                text: _("A sparse file will be created.")
            }],
            triggers: {
                folder: {
                    cls: Ext.baseCSSPrefix + "form-folder-trigger",
                    handler: "onTriggerClick"
                }
            },
            onTriggerClick: function() {
                Ext.create("OmvExtras.window.RootFolderBrowser", {
                    listeners: {
                        scope: this,
                        select: function(wnd, node, path) {
                            // Set the selected path.
                            this.setValue(path);
                        }
                    }
                }).show();
            }
        },{
            xtype: "numberfield",
            name: "imagesize",
            fieldLabel: _("Image Size"),
            allowBlank: false,
            plugins: [{
                ptype: "fieldinfo",
                text: _("Image size in gigabytes.")
            }]
        }];
    }
});

Ext.define("OMV.module.admin.service.tgt.Images", {
    extend: "OMV.workspace.grid.Panel",
    requires: [
        "OMV.Rpc",
        "OMV.data.Store",
        "OMV.data.Model",
        "OMV.data.proxy.Rpc"
    ],
    uses: [
        "OMV.module.admin.service.tgt.Image"
    ],

    hideEditButton: true,
    hidePagingToolbar: false,
    stateful: true,
    stateId: "a0a3e3c8-4dee-11ea-9fbd-03c135b78a82",
    columns: [{
        text: _("Path"),
        sortable: true,
        dataIndex: "path",
        stateId: "path"
    },{
        xtype: "textcolumn",
        text: _("Image size"),
        sortable: true,
        dataIndex: "imagesize",
        stateId: "imagesize",
        renderer: OMV.module.services.downloader.util.Format.fsRenderer
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
                        { name: "path", type: "string" },
                        { name: "imagesize", type: "integer" }
                    ]
                }),
                proxy: {
                    type: "rpc",
                    rpcData: {
                        service: "Tgt",
                        method: "getImageList"
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

    getTopToolbarItems: function() {
        var me = this;
        var items = me.callParent(arguments);
        Ext.Array.push(items, {
            id: me.getId() + "-grow",
            xtype: "button",
            text: _("Grow"),
            iconCls: "x-fa fa-expand",
            handler: me.onGrowButton,
            scope: me,
            disabled: true,
            selectionConfig: {
                minSelections: 1,
                maxSelections: 1
            }
        });
        return items;
    },

    onAddButton: function() {
        var me = this;
        Ext.create("OMV.module.admin.service.tgt.Image", {
            title: _("Add Image"),
            uuid: OMV.UUID_UNDEFINED,
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
                method: "deleteImage",
                params: {
                    uuid: record.get("uuid")
                }
            }
        });
    },

    onGrowButton: function() {
        var me = this;
        var record = me.getSelected();
        var current = record.get("imagesize") / (1024*1024*1024);
        var amount = prompt(_("Enter new size in gigabytes.  Current size = ") + current + _(" GiB"), "");
        if (amount <= current) {
            alert(_("New size must be larger than existing size."));
            return;
        }
        OMV.Rpc.request({
            scope: me,
            rpcData: {
                service: "Tgt",
                method: "growImage",
                params: {
                    uuid: record.get("uuid"),
                    amount: amount
                }
            }
        });
        me.doReload();
    }
});

OMV.WorkspaceManager.registerPanel({
    id: "images",
    path: "/service/tgt",
    text: _("Images"),
    position: 30,
    className: "OMV.module.admin.service.tgt.Images"
});
