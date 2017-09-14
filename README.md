# hello-world-via-snmp
'Hello World' done via SNMP

"Hello world" is the common starting place for most anyone learning a new language. So it seems a good tongue-in-cheek way to introduce sending a notification in the Simple Network Management Protocol (SNMP).

The scripts in this repository demonstrate how to use SNMP v1, v2c and v3 for sending a notification wherein the message can be abritrarily provided.  As well, the scripts show how this can be done using three different means of accessing SNMP: the net-snmp package (common unix/linix platforms), the Perl Net::SNMP package, and the NerveCenter product.

For SNMPv1 the only form of notification is the Trap.  This expands in SNMPv2 where a notification can sent as a Trap or an Inform. And for SNMPv3, the Trap or Inform can be both signed and encrypted.
