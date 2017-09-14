#!/opt/OSInc/bin/perl
#----------------------------------------------------------------------------
#  SNMPv2cHelloWorld.pl
#     Demonstrates how to generate a fictional SNMP v2c Trap or Inform using
#     a choice of SNMP stacks: NerveCenter or net-snmp or Perl Net::SNMP. This
#     script demonstrates the basics of how to use each of these SNMP stacks
#     and issue a SNMP v2c notification.
#
#     The purpose of this sample is to show how you could take arbitrary text
#     message, package it and send it using SNMP.
#
#  This script was prepared for NerveCenter. You are welcome to copy and
#  modify it.
#

use strict;
use warnings;

#----------------------------------------------------------------------------
#  usage: print usage statement to standard output.
sub usage {
    print <<MESSAGE

SNMPv2cHelloWorld:

Sends a SNMPv2c Trap or Inform to the stated destination.  The Trap contains
the message "Hello World" or else one of your choosing.

The destination is either a hostname or an IP Address on your network.


   Usage: SNMPv2cHelloWorld.pl [OPTIONS] destination [message]

   Example: SNMPv2cHelloWorld.pl 10.1.2.3
       Sends a SNMPv2c Trap containing "Hello World" to 10.1.2.3.

   Example: SNMPv2cHelloWorld.pl --stack=net-snmp 10.1.2.3
       Same, but using the net-snmp 'sendtrap' utility.

   Example: SNMPv2cHelloWorld.pl --stack=net::snmp 10.1.2.3
       Same, but using the Perl Net::SNMP module (see cpan.org)

   Example: SNMPv2cHelloWorld.pl 10.1.2.3 "We are the champions"
       Sends to 10.1.2.3 a SNMPv2c Trap containing the message "We
       are the champions" instead of "Hello world"

   Example: SNMPv2cHelloWorld.pl -m "We are the champions" 10.1.2.3
       Same, but using the "--message=Message" option.

   Example: SNMPv2cHelloWorld.pl --inform 10.1.2.3
       Sends a SNMPv2c Inform containing "Hello world" to 10.1.2.3


   destination    The hostname or IP address of where the Trap is to be sent.
       
   OPTIONS
       --stack="NerveCenter"|"net-snmp"|"net::snmp"
           Name the SNMP Stack to be used for sending the Trap.
           "NerveCenter" (default) uses /opt/OSInc/bin/trapgen
           "net-snmp" uses /usr/bin/snmptrap (rpm: net-snmp-utils)
           "net::snmp" uses the Perl Net::SNMP module (See cpan.org)
       --(inform|trap)
           Send either an Inform or a Trap. The default is to send a Trap.
       --version
           State the version of the toolset.
       --help
           This usage statement.

MESSAGE
;
}

#----------------------------------------------------------------------------
#  version: print version information to standard output.
sub version {
    print "Perl $^X: " . $^V . "\n\n";

    print "NerveCenter /opt/OSInc/bin/trapgen:\n";
    if ( -e '/opt/OSInc/nc/bin/trapgen') {
        my $str = `/opt/OSInc/bin/trapgen -ver`;
        print $str;
    } else {
        print "   /opt/OSInc/bin/trapgen not installed\n\n";
    }
    
    print "net-snmp /usr/bin/snmptrap: ";
    if ( -x '/usr/bin/snmptrap' ) {
        `/usr/bin/snmptrap -V`;
    } else {
        print "not installed\n  Install net-snmp-utils\n";
    }

    print "\nPerl Net::SNMP module: ";
    my $is = eval { require Net::SNMP; 1; };
    if ( defined $is ) {
       {
           print $INC{"Net/SNMP.pm"} . ": ";

           require Net::SNMP;
           print Net::SNMP->VERSION . "\n";
       };
    } else {
       print "not installed\n  See cpan.org\n";
    }
}

#----------------------------------------------------------------------------
#  resolve_hostname: return the IP address of a given hostname.
sub resolve_hostname {
    require Net::DNS::Resolver;

    my ( $hostname ) = @_;

    # if passed an IP address at hostname, simply return it.
    return $hostname if $hostname =~ m/\d{1,2}.\d{1,3}.\d{1,3}.\d{1,3}/;

    my $result;

    my $resolver = new Net::DNS::Resolver();
    $resolver->force_v4(1);

    my $packet = $resolver->query( $hostname, 'A', 'IN' );

    if ( defined $packet ) {
        foreach my $rr ( $packet->answer ) {
            next unless $rr->type eq "A";
            $result = $rr->address;
            last;
        }
    }

    $result;
}

#----------------------------------------------------------------------------
#  1. Process the command-line

use Getopt::Long;

my $snmp_stack = "NerveCenter";
my $sendInform;
my $sendTrap;
my $message = "Hello world";
my $show_version;
my $show_help;

my $result = GetOptions( "stack=s" => \$snmp_stack,
                         "inform" => \$sendInform,
                         "trap" => \$sendTrap,
                         "message" => \$message,
                         "version" => \$show_version,
                         "help" => \$show_help );

if ( lc $snmp_stack ne "nervecenter" && lc $snmp_stack ne "net-snmp" && lc $snmp_stack ne "net::snmp" ) {
    print STDERR "ERROR> SNMP Stack must be either 'NerveCenter' or 'net-snmp' or 'Net::SNMP'\n";
    print STDERR "    --stack='NerveCenter'   (Sends notification with NerveCenter trapgen utility)\n";
    print STDERR "    --stack='net-snmp'      (Sends notification with net-snmp sendtrap utility)\n";
    print STDERR "    --stack='net::snmp'     (Sends notification with Perl Net::SNMP module)\n";
    exit( 1 );
}

if ( defined( $show_version ) ) {
    version();
    exit( 0 );
}
    
if ( defined( $show_help ) ) {
    usage();
    exit( 0 );
}

# Note the above GetOption call has removed any of its indicated options
# from ARGV, thus ARGV should now have only the destination and the optional
# agent arguments.
my $num_args = $#ARGV + 1;
if ( $num_args != 1 && $num_args != 2 ) {
    usage();
    exit 1;
}

my $destination = $ARGV[0];
my $destination_port = 162;

if ( defined $ARGV[1] ) {
    $message = $ARGV[1];
}

my $hostname = `hostname`;
chomp $hostname;

#----------------------------------------------------------------------------
#  2. The following are facts for standard SNMP usage.

use constant { # Object Identifiers (OIDs) used to name Traps and Informs
               # in SNMP v2c and v3.
    coldStart => "1.3.6.1.6.3.1.1.5.1",   # See RFC3418
    warmStart => "1.3.6.1.6.3.1.1.5.2",
    linkDown => "1.3.6.1.6.3.1.1.5.3",
    linkUp => "1.3.6.1.6.3.1.1.5.4",
    authenticationFailure => "1.3.6.1.6.3.1.1.5.5",
    egpNeighborLoss => "1.3.6.1.6.3.1.1.5.6"
};

use constant {  # OIDs for varbinds used in SNMP v2c/v3 Traps and Informs
  # Required for all Trap and Informs:
    sysUpTime =>   "1.3.6.1.2.1.1.3",     # TIMETICKS. SNMPv2-MIB. This is the required 1st varbind
    snmpTrapOID => "1.3.6.1.6.3.1.1.4.1", # OBJECT_IDENTIFIER. SNMPv2-MIB. This is the required 2nd varbind
};

#----------------------------------------------------------------------------
#  3. The fields of a SNMP v2c Trap or Inform PDU

my $timestamp = 10;
my $community = "public";

my $enterpriseOID = "1.3.6.1.4.1.78";

my $trapOID = "$enterpriseOID.0.12345";

my $messageOID = "$trapOID.1"; # OID of the payload message

#----------------------------------------------------------------------------
#  4a. Build and Issue the command. (NerveCenter SNMP stack)

if ( lc $snmp_stack eq "nervecenter" ) {
    my $pduType = "";
    if ( $sendInform ) {
        $pduType = "-v2cinform -w";
    }

    my $enterprise = "-";

    # Load the trap/inform data payload.
    my $varbinds = "$messageOID octetstring \"$message\"";

    my $command = "/opt/OSInc/bin/trapgen -v2c -c $community $pduType $destination $enterprise $trapOID $timestamp $varbinds";

    print "Command: " . $command . "\n";

    `$command`;
}

#----------------------------------------------------------------------------
#  4b. Build and Issue the command. (net-snmp SNMP stack)

elsif ( lc $snmp_stack eq "net-snmp" ) {
    my $command = "/usr/bin/snmptrap ";

    if ( $sendInform ) {
        $command = "/usr/bin/snmpinform ";
    }

    # Load the trap/inform data payload.
    my $varbinds = "$messageOID s \"$message\"";

    $command = "$command -v 2c -c $community $destination:$destination_port $timestamp $trapOID $varbinds";

    print "Command: " . $command . "\n";

    `$command`;

}

#----------------------------------------------------------------------------
#  4c. Build and Issue the command. (Perl Net::SNMP)

else { # Net::SNMP stack

    # Test whether the invoked Perl environment contains the needed Net::SNMP
    # module. For example, the Perl environment known to /bin/perl likely does
    # not; however, the Perl environment at /opt/OSInc/perl/bin/perl does.
    defined( eval { require Net::SNMP; 1; } ) || die "Perl Net::SNMP not present\n";
    # If you get the above message, then try "/opt/OSInc/bin/perl" insead of
    # "/bin/perl" when you run this script. Use "which perl" to see which Perl
    # environment your $PATH is set up to use.

    require Net::SNMP;
    my $snmp = Net::SNMP->session(
                              -hostname       => $destination,
                              -port           => $destination_port,
                              -version        => 2,
                              -community      => $community
                          );

    die "Perl Net::SNMP unable to setup SNMP Stack to $destination:$destination_port" if not defined $snmp;


    my @varbinds = (
                       sysUpTime . ".0", Net::SNMP->TIMETICKS, $timestamp,
                       snmpTrapOID . ".0", Net::SNMP->OBJECT_IDENTIFIER, $trapOID
                   );

    # Load the trap/inform data payload.
    push @varbinds, ( $messageOID, Net::SNMP->OCTET_STRING, $message );

    my $outcome;

    if ( $sendInform ) {
        $outcome = $snmp->inform_request( -varbindlist => \@varbinds );
    } else {
        $outcome = $snmp->snmpv2_trap( -varbindlist => \@varbinds );
    }

    if ( not defined $outcome ) {
        print "Perl Net::SNMP did not send the Trap. " . $snmp->error() . "\n";
    } elsif ( $outcome == 0 ) {
        print "Perl Net::SNMP did not send the Trap. " . $snmp->error() . "\n";
    }

    $snmp->close();
}

exit 0;
