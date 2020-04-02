#!/bin/bash

: '
------- No supported in production -------
Enable remote access VPN on Autoscaling Gateway
Needs to be run in Autoprovision template with "ACTIVATESNXVPN" as a custom parameter
------- No supported in production -------
'

. /var/opt/CPshrd-R80.40/tmp/.CPprofile.sh

AUTOPROV_ACTION=$1
GW_NAME=$2
CUSTOM_PARAMETERS=$3

if [[ $AUTOPROV_ACTION == delete ]]
then

	echo "Connection to API server"
	SID=$(mgmt_cli -r true login -f json | jq -r '.sid')
	GW_JSON=$(mgmt_cli --session-id $SID show simple-gateway name $GW_NAME -f json)
	GW_UID=$(echo $GW_JSON | jq '.uid')
	echo "Finding the RemoteAccess UID"
	REMOTE_ACCESS_UID=$(mgmt_cli --session-id $SID show-generic-objects name "RemoteAccess" -f json | jq '.objects[].uid')

	echo "Removing $GW_NAME to Remote Access Community"
		REMOTE_ACCESS_UID=$(mgmt_cli --session-id $SID show-generic-objects name "RemoteAccess" -f json | jq '.objects[].uid')
		mgmt_cli --session-id $SID set generic-object uid $REMOTE_ACCESS_UID participantGateways.remove $GW_UID
		
	echo "Publishing changes"
		mgmt_cli publish --session-id $SID
		
		exit 0
fi

if [[ $CUSTOM_PARAMETERS != ACTIVATESNXVPN ]];
then
	exit 0
fi

LOG_FILE=$FWDIR/log/mabactivation.elg

log(){
TIME=$(date "+%Y-%m-%d_%H:%M:%S")
echo "$TIME - $1" >> $LOG_FILE
}

log "***********************************************"
log "Launching COMMAND: $AUTOPROV_ACTION for Gateway:$GW_NAME"
log "***********************************************"

log "Connection to API server"
SID=$(mgmt_cli -r true login -f json | jq -r '.sid')
GW_JSON=$(mgmt_cli --session-id $SID show simple-gateway name $GW_NAME -f json)
GW_UID=$(echo $GW_JSON | jq '.uid')
GW_ETH0_IP=$(echo $GW_JSON | jq -r '."ipv4-address"')
OFFICE_MODE_POOL=$(mgmt_cli --session-id $SID show-network name CP_default_Office_Mode_addresses_pool -f json |jq '.uid')
INSTALL_STATUS=1
POLICY_PACKAGE_NAME="azureinbound-RB"
ANY_UID=$(mgmt_cli --session-id $SID show-generic-objects name Any details-level full -f json | jq -r '.objects[] | select(.cpmiDisplayName=="Any") |.uid')

if [[ $AUTOPROV_ACTION == add ]]
then
		
        echo "Finding the RemoteAccess UID"
	    REMOTE_ACCESS_UID=$(mgmt_cli --session-id $SID show-generic-objects name "RemoteAccess" -f json | jq '.objects[].uid')
 		
		echo "Adding $GW_NAME to Remote Access Community"
		mgmt_cli --session-id $SID set generic-object uid $REMOTE_ACCESS_UID participantGateways.add $GW_UID               
        
		echo "Set VPN Static NAT to $GW_ETH0_IP"
        mgmt_cli --session-id $SID set-generic-object uid $GW_UID vpn.singleVpnIp $GW_ETH0_IP vpn.ipResolutionMechanismGw "SINGLENATIPVPN" vpn.useCert "defaultCert" vpn.useClientlessVpn true
	
		log "Activating syncWebUiPortWithGwFlag on $GW_NAME" 
		mgmt_cli --session-id $SID set generic-object uid $GW_UID syncWebUiPortWithGwFlag true
					
		echo "Configuration VPNDomain"
		mgmt_cli --session-id $SID set simple-gateway uid $GW_UID vpn-settings.vpn-domain GRP_cloudcidr vpn-settings.vpn-domain-type manual
				
		echo "Cleaning dataSourceSettings on $GW_NAME" 
		mgmt_cli --session-id $SID set generic-object uid $GW_UID dataSourceSettings null
		
		echo "Cleaning nat on $GW_NAME" 
		mgmt_cli --session-id $SID set generic-object uid $GW_UID nat null		
		
		echo "Modifying SecurePlatform portal"
		PORTALID=$(mgmt_cli -r true show generic-object uid $GW_UID --format json | jq '.portals[0].objId' | tr -d '"')
		ORIGINALURL=$(mgmt_cli -r true show generic-object uid $GW_UID --format json | jq '.portals[0].mainUrl' | tr -d '"' | sed 's/.$//')
		mgmt_cli --session-id $SID set generic-object uid $GW_UID portals.set.uid $PORTALID portals.set.owned-object.mainUrl "\"$ORIGINALURL:4434/\""

		echo "Creating VPNSNX portal on $GW_NAME" 
		mgmt_cli --session-id $SID set generic-object uid $GW_UID portals.add.create "com.checkpoint.objects.classes.dummy.CpmiPortalSettings" portals.add.owned-object.portalName "\"VPN_SNX\""
		#SNX_PORTAL_ID=$(mgmt_cli --session-id $SID show generic-object uid $GW_UID --format json | jq -r '.portals[3].objId')
		echo "Checking to see if SNX portal is already created"
        SNX_PORTAL_ID=$(mgmt_cli --session-id $SID show-generic-object uid $GW_UID --format json | jq -r '.portals[] | select(.portalName=="VPN_SNX") | .objId')
		
		echo "Setting client portal access on all interfaces on $GW_NAME" 
		mgmt_cli --session-id $SID set generic-object uid $GW_UID portals.set.uid $SNX_PORTAL_ID portals.set.owned-object.portalAccess "ALL_INTERFACES"

		echo "Setting client portal allowed IPs on $GW_NAME" 
		mgmt_cli --session-id $SID set generic-object uid $GW_UID portals.set.uid $SNX_PORTAL_ID portals.set.owned-object.ipAddress "0.0.0.0"

		echo "Setting client portal internal port on $GW_NAME" 
		mgmt_cli --session-id $SID set generic-object uid $GW_UID portals.set.uid $SNX_PORTAL_ID portals.set.owned-object.internalPort 444
		
		echo "Setting client portal mainURL on $GW_NAME" 
		mgmt_cli --session-id $SID set generic-object uid $GW_UID portals.set.uid $SNX_PORTAL_ID portals.set.owned-object.mainUrl "https://0.0.0.0/"

		echo "Creating CSHELL portal on $GW_NAME" 
		mgmt_cli --session-id $SID set generic-object uid $GW_UID portals.add.create "com.checkpoint.objects.classes.dummy.CpmiPortalSettings" portals.add.owned-object.portalName "\"CSHELL\""
		#CSHELL_PORTAL_ID=$(mgmt_cli --session-id $SID show generic-object uid $GW_UID --format json | jq -r '.portals[4].objId')
		echo "Checking to see if CSHELL portal is already created"
		CSHELL_PORTAL_ID=$(mgmt_cli --session-id $SID show-generic-object uid $GW_UID --format json | jq -r '.portals[] | select(.portalName=="CSHELL") | .objId')
		
		echo "Setting client portal access on all interfaces on $GW_NAME" 
		mgmt_cli --session-id $SID set generic-object uid $GW_UID portals.set.uid $CSHELL_PORTAL_ID portals.set.owned-object.portalAccess "ALL_INTERFACES"

		echo "Setting client portal allowed IPs on $GW_NAME" 
		mgmt_cli --session-id $SID set generic-object uid $GW_UID portals.set.uid $CSHELL_PORTAL_ID portals.set.owned-object.ipAddress "0.0.0.0"

		echo "Setting client portal internal port on $GW_NAME" 
		mgmt_cli --session-id $SID set generic-object uid $GW_UID portals.set.uid $CSHELL_PORTAL_ID portals.set.owned-object.internalPort 444
		
		echo "Setting client portal mainURL on $GW_NAME" 
		mgmt_cli --session-id $SID set generic-object uid $GW_UID portals.set.uid $CSHELL_PORTAL_ID portals.set.owned-object.mainUrl "https://0.0.0.0/CSHELL"

		echo "Creating CLIENTS portal on $GW_NAME" 
		mgmt_cli --session-id $SID set generic-object uid $GW_UID portals.add.create "com.checkpoint.objects.classes.dummy.CpmiPortalSettings" portals.add.owned-object.portalName "\"clients\""
		#CLIENTS_PORTAL_ID=$(mgmt_cli --session-id $SID show generic-object uid $GW_UID --format json | jq -r '.portals[5].objId')
		echo "Checking to see if CLIENTS portal is already created"
		CLIENTS_PORTAL_ID=$(mgmt_cli --session-id $SID show-generic-object uid $GW_UID --format json | jq -r '.portals[] | select(.portalName=="clients") | .objId')
		
		echo "Setting client portal access on all interfaces on $GW_NAME" 
		mgmt_cli --session-id $SID set generic-object uid $GW_UID portals.set.uid $CLIENTS_PORTAL_ID portals.set.owned-object.portalAccess "ALL_INTERFACES"

		echo "Setting client portal allowed IPs on $GW_NAME" 
		mgmt_cli --session-id $SID set generic-object uid $GW_UID portals.set.uid $CLIENTS_PORTAL_ID portals.set.owned-object.ipAddress "0.0.0.0"

		echo "Setting client portal internal port on $GW_NAME" 
		mgmt_cli --session-id $SID set generic-object uid $GW_UID portals.set.uid $CLIENTS_PORTAL_ID portals.set.owned-object.internalPort 444
		
		echo "Setting client portal mainURL on $GW_NAME" 
		mgmt_cli --session-id $SID set generic-object uid $GW_UID portals.set.uid $CLIENTS_PORTAL_ID portals.set.owned-object.mainUrl "https://0.0.0.0/clients"

		echo "Configuring OfficeMode Pool on $GW_NAME"
		mgmt_cli --session-id $SID set generic-object uid $GW_UID firewallSetting.ipAssignmentSettings.create "com.checkpoint.objects.classes.dummy.CpmiIpAssignmentSettings" firewallSetting.ipAssignmentSettings.owned-object.omIppool $OFFICE_MODE_POOL

		echo "Allowing OfficeMode to all users on $GW_NAME" 
		mgmt_cli --session-id $SID set generic-object uid $GW_UID firewallSetting.ipAssignmentOffer "ALWAYS"

		echo "Configuring Anti-Spoofing for OfficeMode on $GW_NAME" 
		mgmt_cli --session-id $SID set generic-object uid $GW_UID firewallSetting.ipAssignmentSettings.omAdditionalIpForAntiSpoofing $OFFICE_MODE_POOL

		echo "Adding ANY on IA idServerGatewayWeak "
		mgmt_cli --session-id $SID set generic-object uid $GW_UID identityAwareBlade.idServerGatewayWeak.add $ANY_UID
		
		echo "Activating Anti-Spoofing for OfficeMode on $GW_NAME" 
		mgmt_cli --session-id $SID set generic-object uid $GW_UID firewallSetting.ipAssignmentSettings.omPerformAntispoofing true

		echo "Configuring usbl on VpnClientSettings on $GW_NAME" 
		mgmt_cli --session-id $SID set generic-object uid $GW_UID vpn.vpnClientsSettingsForGateway.usb1VpnClientSettings.create "com.checkpoint.objects.classes.dummy.CpmiUsb1VpnClientSettingsForGateway"

		echo "Setting up visitor mode on $GW_NAME"
		mgmt_cli --session-id $SID set generic-object uid $GW_UID vpn.tcpt.active true

		echo "Setting up visitor mode on $GW_NAME"
		mgmt_cli --session-id $SID set generic-object uid $GW_UID vpn.sslNe.sslEnable true

		echo "Enable Remote Access on IA Blade"
		mgmt_cli --session-id $SID set generic-object uid $GW_UID identityAwareBlade.enableRemoteAccess true 

		echo "Creating Auth Schemes"
		mgmt_cli --session-id $SID set generic-object uid $GW_UID realmsForBlades.add.create "com.checkpoint.objects.classes.dummy.CpmiRealmBladeEntry" realmsForBlades.add.owned-object.ownedName "vpn" realmsForBlades.add.owned-object.requirePasswordInFirstChallenge true realmsForBlades.add.owned-object.displayString "Standard" realmsForBlades.add.owned-object.authentication.authSchemes.add.create "com.checkpoint.objects.realms_schema.dummy.CpmiRealmAuthScheme" realmsForBlades.add.owned-object.authentication.authSchemes.add.owned-object.authScheme "USER_PASS"
		mgmt_cli --session-id $SID set-generic-object uid $GW_UID realmsForBlades.add.create "com.checkpoint.objects.classes.dummy.CpmiRealmBladeEntry" realmsForBlades.add.owned-object.ownedName "ssl_vpn" realmsForBlades.add.owned-object.displayString "ssl_vpn" realmsForBlades.add.owned-object.requirePasswordInFirstChallenge false realmsForBlades.add.owned-object.authentication.authSchemes.add.create "com.checkpoint.objects.realms_schema.dummy.CpmiRealmAuthScheme" realmsForBlades.add.owned-object.authentication.authSchemes.add.owned-object.authScheme "USER_PASS"
		mgmt_cli --session-id $SID set-generic-object uid $GW_UID realmsForBlades.add.create "com.checkpoint.objects.classes.dummy.CpmiRealmBladeEntry" realmsForBlades.add.owned-object.ownedName "mobile_realm" realmsForBlades.add.owned-object.displayString "mobile_realm" realmsForBlades.add.owned-object.requirePasswordInFirstChallenge false realmsForBlades.add.owned-object.authentication.authSchemes.add.create "com.checkpoint.objects.realms_schema.dummy.CpmiRealmAuthScheme" realmsForBlades.add.owned-object.authentication.authSchemes.add.owned-object.authScheme "USER_PASS"
		mgmt_cli --session-id $SID set-generic-object uid $GW_UID realmsForBlades.add.create "com.checkpoint.objects.classes.dummy.CpmiRealmBladeEntry" realmsForBlades.add.owned-object.ownedName "active_sync_realm" realmsForBlades.add.owned-object.displayString "active_sync_realm" realmsForBlades.add.owned-object.requirePasswordInFirstChallenge false realmsForBlades.add.owned-object.authentication.authSchemes.add.create "com.checkpoint.objects.realms_schema.dummy.CpmiRealmAuthScheme" realmsForBlades.add.owned-object.authentication.authSchemes.add.owned-object.authScheme "USER_PASS"
		mgmt_cli --session-id $SID set-generic-object uid $GW_UID realmsForBlades.add.create "com.checkpoint.objects.classes.dummy.CpmiRealmBladeEntry" realmsForBlades.add.owned-object.ownedName "mobile_android_bc" realmsForBlades.add.owned-object.displayString "mobile_android_bc" realmsForBlades.add.owned-object.requirePasswordInFirstChallenge false realmsForBlades.add.owned-object.authentication.authSchemes.add.create "com.checkpoint.objects.realms_schema.dummy.CpmiRealmAuthScheme" realmsForBlades.add.owned-object.authentication.authSchemes.add.owned-object.authScheme "USER_PASS"
		
		log "Publishing 1st changes"
		mgmt_cli publish --session-id $SID
		
		echo "Change color"
		mgmt_cli --session-id $SID set simple-gateway uid $GW_UID color pink
		
		log "Publishing 2nd changes"
		mgmt_cli publish --session-id $SID		
      
		log "Start Install Policy"
		#Try to install policy until it get properly installed (to avoid policy install bypass in case another one is installing at the same time)
		until [[ $INSTALL_STATUS != 1 ]]; do
		mgmt_cli --session-id $SID install-policy policy-package $POLICY_PACKAGE_NAME targets $GW_UID --format json
		INSTALL_STATUS=$?
		done
		
		log "Policy Installed" 

                log "Logging out of session"
                mgmt_cli logout --session-id $SID
		
		echo "***********************************************"
		echo "END OF COMMAND: $AUTOPROV_ACTION for Gateway:$GW_NAME with $4"
		echo "***********************************************"
				
				
		exit 0
fi
	
log "Logout from API server"
mgmt_cli --session-id $SID logout
			
exit 0
