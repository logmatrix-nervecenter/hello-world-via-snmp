#!/opt/OSInc/bin/perl
#----------------------------------------------------------------------------
#  SNMPv1HelloWorld.pl
#     Demonstrates how to generate a fictional SNMP v1 Trap using one of a
#     choice of SNMP stacks: NerveCenter or net-snmp or Perl Net::SNMP. This
#     script demonstrates the basics of how to use each of these SNMP stacks
#     and issue a SNMP v1 notification.
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

SNMPv1HelloWorld:

Sends a SNMPv1 Trap to the stated destination.  The Trap contains the
message "Hello World" or else one of your choosing.

The destination is either a hostname or an IP Address on your network.


   Usage: SNMPv1HelloWorld.pl [OPTIONS] destination [message]

   Example: SNMPv1HelloWorld.pl 10.1.2.3
       Sends a SNMPv1 Trap containing "Hello World" to 10.1.2.3.

   Example: SNMPv1HelloWorld.pl --stack=net-snmp 10.1.2.3
       Same, but using the net-snmp 'sendtrap' utility.

   Example: SNMPv1HelloWorld.pl --stack=net::snmp 10.1.2.3
       Same, but using the Perl Net::SNMP module (see cpan.org)

   Example: SNMPv1HelloWorld.pl 10.1.2.3 "We are the champions"
       Sends to 10.1.2.3 a SNMPv1 Trap containing the message "We
       are the champions" instead of "Hello world"

   Example: SNMPv1HelloWorld.pl -m "We are the champions" 10.1.2.3
       Same, but using the "--message=Message" option.



   OPTIONS
       --stack="NerveCenter"|"net-snmp"|"net::snmp"
           Name the SNMP Stack to be used for sending the Trap.
           "NerveCenter" (default) uses /opt/OSInc/bin/trapgen
           "net-snmp" uses /usr/bin/snmptrap (rpm: net-snmp-utils)
           "net::snmp" uses the Perl Net::SNMP module (See cpan.org)
       --message=Message
           Issue the trap using the provided Message instead of
           the 'Hello world' default.

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
my $show_version;
my $message = "Hello world";
my $show_help;

my $result = GetOptions( "stack=s" => \$snmp_stack,
                         "version" => \$show_version,
                         "message=s" => \$message,
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

if ( defined $ARGV[1] ) {
    $message = $ARGV[1];
}

#----------------------------------------------------------------------------
#  2. The following are facts for standard SNMP usage.

# A SNMP v1 Trap *must* specify a Generic ID using this range
#    (See RFC 1157:  http://tools.ietf.org/html/rfc1157
use constant {
    coldStart => '0',              # RFC 1157 section 4.1.6.1
    warmStart => '1',              # RFC 1157 section 4.1.6.2
    linkDown => '2',               # RFC 1157 section 4.1.6.3
    linkUp => '3',                 # RFC 1157 section 4.1.6.4
    authenticationFailure => '4',  # RFC 1157 section 4.1.6.5
    egpNeighborLoss => '5',        # RFC 1157 section 4.1.6.6
    enterpriseSpecific => '6'      # RFC 1157 section 4.1.6.7
};

#----------------------------------------------------------------------------
#  3. The fields of a SNMP v1 Trap PDU, plus the destination.

my $destination = $ARGV[0];
my $destination_port = 162;

my $agent_in = `hostname`;
chomp $agent_in;
my $agent = resolve_hostname $agent_in;
die "Unable to resolve Agent $agent_in to IP address" if not defined $agent;

my $enterpriseOID = '1.3.6.1.4.1.78'; # LogMatrix
my $timestamp = 100;
my $community = "public";
my $genericId = enterpriseSpecific;
my $specificId = '12345';

my $baseTrapVB = join( ".", $enterpriseOID, 0, $specificId );   # 1.3.6.1.4.1.78.0.12345

my $messageVB =     "$baseTrapVB.1"; # OID of the payload message


#----------------------------------------------------------------------------
#  4a . Build and issue the command using NerveCenter SNMP Stack

if ( lc $snmp_stack eq "nervecenter" ) {
    my $varbinds = "$messageVB octetstring \"$message\"";

    my $command= "/opt/OSInc/bin/trapgen -v1 -c $community -p $destination_port $destination $enterpriseOID $agent $genericId $specificId $timestamp $varbinds";

    print "Command: " . $command . "\n";

    if ( defined($command) && length($command) > 0 ) {
        `$command`;
    }
}

#----------------------------------------------------------------------------
#  4a . Build and issue the command using net-snmp SNMP Stack

elsif ( lc $snmp_stack eq "net-snmp" ) {
    my $varbinds = "$messageVB s \"$message\"";

    my $command = "/usr/bin/snmptrap -v 1 -c $community $destination:$destination_port $enterpriseOID $agent $genericId $specificId $timestamp $varbinds";

    print "Command: " . $command . "\n";

    if ( defined($command) && length($command) > 0 ) {
        `$command`;
    }

} else { # Net::SNMP stack

    # Test whether the invoked Perl environment contains the needed Net::SNMP
    # module. For example, the Perl environment known to /bin/perl likely does
    # not; however, the Perl environment at /opt/OSInc/perl/bin/perl does.
    defined( eval { require Net::SNMP; 1; } ) || die "Perl Net::SNMP not present\n";
    # If you get the above message, then try "/opt/OSInc/bin/perl" insead of
    # "/bin/perl" when you run this script. Use "which perl" to see which Perl
    # environment your $PATH is set up to use.

    my @varbinds;  # Each varbind is a triplet of OID + DataType + Value
    push @varbinds, ( $messageVB, Net::SNMP->OCTET_STRING, $message );

    require Net::SNMP;
    my $snmp = Net::SNMP->session(
                              -hostname       => $destination,
                              -port           => $destination_port,
                              -community      => $community
                          );

    die "Perl Net::SNMP unable to setup SNMP Stack to $destination:$destination_port" if not defined $snmp;

    my $outcome = $snmp->trap(
                             -agentaddr      => $agent,
                             -enterprise     => $enterpriseOID,
                             -generictrap    => $genericId,
                             -specifictrap   => $specificId,
                             -timestamp      => $timestamp,
                             -varbindlist    => \@varbinds
                         );
    if ( not defined $outcome ) {
        print "Perl Net::SNMP did not send the Trap. " . $snmp->error() . "\n";
    } elsif ( $outcome == 0 ) {
        print "Perl Net::SNMP did not send the Trap. " . $snmp->error() . "\n";
    }

    $snmp->close();
}

exit 0;
#----------------------------------------------------------------------------
#  ###
