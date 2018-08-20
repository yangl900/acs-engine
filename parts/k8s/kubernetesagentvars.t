{{if .IsWindows}}
        "winResourceNamePrefix" : "[substring(variables('nameSuffix'), 0, 5)]",
{{end}}

"{{.Name}}Count": "[parameters('{{.Name}}Count')]",
"{{.Name}}Variables":
{
    {{if .IsStorageAccount}}
        "StorageAccountOffset": "[mul(variables('maxStorageAccountsPerAgent'),variables('{{.Name}}Index'))]",
        "StorageAccountsCount": "[add(div(variables('{{.Name}}Count'), variables('maxVMsPerStorageAccount')), mod(add(mod(variables('{{.Name}}Count'), variables('maxVMsPerStorageAccount')),2), add(mod(variables('{{.Name}}Count'), variables('maxVMsPerStorageAccount')),1)))]",
    {{end}}
        "Offset": "[parameters('{{.Name}}Offset')]",
        "AvailabilitySet": "[concat('{{.Name}}-availabilitySet-', variables('nameSuffix'))]",
    {{if .IsWindows}}
        "VMNamePrefix": "[concat(variables('winResourceNamePrefix'), variables('orchestratorName'), add(900,variables('{{.Name}}Index')))]",
    {{else}}
        "VMNamePrefix": "[concat(variables('orchestratorName'), '-{{.Name}}-', variables('nameSuffix'), '-')]", 
    {{end}}
        "VMSize": "[parameters('{{.Name}}VMSize')]",
    {{if .IsCustomVNET}}
        "VnetSubnetID": "[parameters('{{.Name}}VnetSubnetID')]",
        "SubnetName": "[parameters('{{.Name}}VnetSubnetID')]",
        "VnetParts": "[split(parameters('{{.Name}}VnetSubnetID'),'/subnets/')]",
    {{else}}
        "VnetSubnetID": "[variables('vnetSubnetID')]",
        "SubnetName": "[variables('subnetName')]",
    {{end}}
        "osImageOffer": "[parameters('{{.Name}}osImageOffer')]",
        "osImageSKU": "[parameters('{{.Name}}osImageSKU')]",
        "osImagePublisher": "[parameters('{{.Name}}osImagePublisher')]",
        "osImageVersion": "[parameters('{{.Name}}osImageVersion')]"
},

