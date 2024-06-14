# This script validates if the BGP configuration of an ExpressRoute circuit 
# is aligned to Microsoft's best practices for optimal resilience.
# The script retrieves an ExpressRoute circuit's route tables (primary and secondary) and check if:
# 1) All the routes announced from the customer/partner edge on the primary BGP session are also announced on the secondary BGP session.
# 2) All the routes announced from the customer/partner edge on the secondary BGP session are also announced on the primary BGP session.
# 3) All the routes announced from the customer/partner edge on both BGP sessions have the same AS Path.
#
# Author: Federico Guerrini (fguerri@microsoft.com)


param (
    # The name of the ExpressRoute circuit to be validated
    [string]$ExpressRouteCircuitName,
    # The name of the ExpressRoute circuit's resource group
    [string]$ResourceGroupName,
    # When set to $true, the script generates verbose output with the list of routes that are not properly announced from the customer/partner edge
    [bool]$WhatToFix = $false
)
 
# Retrieve the primary and secondary route tables for the ExpressRoute circuit
$primaryRt = Get-AzExpressRouteCircuitRouteTable -ExpressRouteCircuitName $ExpressRouteCircuitName -ResourceGroupName $ResourceGroupName -PeeringType AzurePrivatePeering -DevicePath Primary
$secondaryRt = Get-AzExpressRouteCircuitRouteTable -ExpressRouteCircuitName $ExpressRouteCircuitName -ResourceGroupName $ResourceGroupName -PeeringType AzurePrivatePeering -DevicePath Secondary

# Remove the routes originated by Azure VNets connected to the circuit
# The routes originated by Azure VNets contain ASN 65515 in their AS Path
$fromOnPremPrimary = $primaryRt | Where-Object { !($_.Path).Contains("65515") }
$fromOnPremSecondary = $secondaryRt | Where-Object { !($_.Path).Contains("65515") }

# Iterate over the routes announced from the customer/partner edge in the primary BGP session
# and extract those that are NOT announced in the secondary BGP session
$fromOnPremPrimaryOnly = $fromOnPremPrimary.Network | Where-Object { $fromOnPremSecondary.Network -notcontains $_ }

# Iterate over the routes announced from the customer/partner edge in the secondary BGP session
# and extract those that are NOT announced in the primary BGP session
$fromOnPremSecondaryOnly = $fromOnPremSecondary.Network | Where-Object { $fromOnPremPrimary.Network -notcontains $_ }

# Iterate over the routes announced from the customer/partner edge in the primary BGP session
# and extract those that are also announced in the secondary BGP session
$fromOnPremBoth = $fromOnPremPrimary.Network | Where-Object { $fromOnPremSecondary.Network -contains $_ }

# Iterate over the routes announced from the customer/partner edge in both BGP sessions and check if they have the same AS Path
$fromOnPremNoEcmp = @()
foreach ($route in $fromOnPremBoth) {
    $primaryIndex = $fromOnPremPrimary.Network.IndexOf($route)
    $secondaryIndex = $fromOnPremSecondary.Network.IndexOf($route)
    if ($fromOnPremPrimary[$primaryIndex].Path -ne $fromOnPremSecondary[$secondaryIndex].Path) {
        $fromOnPremNoEcmp += $route
    }
}

# Generate concise output
$warnings = $false
if ($fromOnPremPrimaryOnly.Count -gt 0) {
    $warnings = $true
    Write-Host "[WARNING]" $fromOnPremPrimaryOnly.Count "routes are announced from on-prem only in the primary BGP session."
} else {
    Write-Host "[OK] No routes are announced from on-prem in the primary BGP session only."
}

if ($fromOnPremSecondaryOnly.Count -gt 0) {
    $warnings = $true
    Write-Host "[WARNING]" $fromOnPremSecondaryOnly.Count "routes are announced from on-prem only in the secondary BGP session."
} else {
    Write-Host "[OK] No routes are announced from on-prem in the secondary BGP session only."
}

if ($fromOnPremNoEcmp.Count -gt 0) {
    $warnings = $true
    Write-Host "[WARNING]" $fromOnPremNoEcmp.Count "routes are announced with different AS Paths in the two BGP sessions.Make sure you understand the implications of preferring one link over the other during planned maintenance (https://learn.microsoft.com/en-us/azure/expressroute/planned-maintenance#maintenance-activity-between-msee-routers-and-microsoft-core-network)."
} else {
    Write-Host "[OK] No routes are announced from on-prem with different AS Paths in the two BGP sessions."
}

# If warning messages have been generated and the user has not requested verbose output
if ((!$WhatToFix) -and $warnings) {
    Write-Host
    Write-Host 'Please run the script with <-WhatToFix $true> to see what needs to be fixed in the customer/partner edge BGP configuration.'
}

# If the user has requested verbose output and there are warnings
if ($WhatToFix -and $warnings) {
    Write-Host 
    Write-host "************************************************************"
    Write-host "What to fix:"
    Write-host "************************************************************"

    foreach ($route in $fromOnPremPrimaryOnly) {
        Write-Host "Announce route $route in the secondary BGP session"
    }
    foreach ($route in $fromOnPremSecondaryOnly) {
        Write-Host "Announce route $route in the primary BGP session"
    }
    foreach ($route in $fromOnPremNoEcmp) {
        Write-Host "Announce route $route in both BGP sessions with the same AS Path"
    }
}

# If the user has requested verbose output and there are no warnings
if ($WhatToFix -and !$warnings) {
    Write-Host 
    Write-host "*********************************************************************************************************"
    Write-Host "The ExpressRoute circuit is correctly configured for ECMP routing over both links. No action is required."
    Write-host "*********************************************************************************************************"
}



