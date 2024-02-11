az container create --name twingate-tangible-agouti --image twingate/connector:1 --resource-group ${resourceName} --vnet ${virtualNetworkName} --subnet ${subnetName} --cpu 1 --memory 2 --environment-variables TWINGATE_NETWORK=ultradev TWINGATE_ACCESS_TOKEN=${accessToken} TWINGATE_REFRESH_TOKEN=${refreshToken} TWINGATE_TIMESTAMP_FORMAT=2