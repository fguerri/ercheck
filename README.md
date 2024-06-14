This script validates if the BGP configuration of an ExpressRoute circuit is aligned to Microsoft's best practices for optimal resilience.
The script retrieves an ExpressRoute circuit's route tables (primary and secondary) and check if:
- All the routes announced from the customer/partner edge on the primary BGP session are also announced on the secondary BGP session.
- All the routes announced from the customer/partner edge on the secondary BGP session are also announced on the primary BGP session.
- All the routes announced from the customer/partner edge on both BGP sessions have the same AS Path.
