package Weather::Product;
require 5.004;
require Exporter;

=head1 NAME

Weather::Product - routines for parsing WMO-style weather products

=head1 DESCRIPTION

Weather::Product is a base module for parsing WMO-style weather products
(as in forecasts, observations, etc.) as might come from various weather
services.

More "sophisiticated" parsing of U.S. National Weather Service (NWS)
weather products (by AWIPS IDs or zones) is done in the
Weather::Product::NWS module (which inherits methods from this module).

=head1 EXAMPLE

    use Weather::Product;

    $forecast = new Weather::Product 'data/text/FPUS61/KOKX.TXT';

    print $forecast->text{FPUS61);

=head1 METHODS

=cut

use vars qw($VERSION);
$VERSION = "1.2.0";

@ISA = qw(Exporter);
@EXPORT = qw();
@EXPORT_OK = qw();

use Carp;
use FileHandle;
use LWP::UserAgent;
use Time::Local;

require Weather::WMO;

=pod

=head2 new

A new weather product may be constructed and initialized the usual fashion:

    $obj = new Weather::Product

or,

    $obj = new Weather::Product LIST

where LIST contains file names or URLs of weather products to I<import>.

=cut

sub new {
    my $this = shift;
    my $class = ref($this) || $this;
    my $self = {};
    bless $self, $class;
    $self->initialize;
    $self->import(@_);
    return $self;
}

sub initialize {
    my $self = shift;

    $self->{count} = 0;			#
    $self->{products} = ();		# products parsed
    $self->{text} = ();			# text
    $self->{WMO} = undef;
}

=pod

=head2 import

    $obj->import LIST

"Imports"  and parses files or URLs containing weather products. This is used
by the I<new> method if files or URLs are specified.

I<import> can be used to update the object with a newer weather product or
to merge additional parts, addendums, etc. (not implemented in this version).

Be aware that the I<parse> method called by I<import> will not allow incompatible
(read: "different") weather products to be imported.  You should create a new
object for each product.

=cut

sub import {
    my $self = shift;
    export $self;

    my @args = @_, $arg, $ua, $req, $res;

# To-do: when importing files or documents from internet, use the
# last-modification time as the base time for int_time() function

    foreach $arg (@args) {
        if (defined($arg)) {
            my $buffer = "";
            if (-r $arg)		# first check if this is a local file
            {
                my $fh = new FileHandle;
                open $fh, "< $arg" or croak "Cannot import $arg";
                while (my $line=<$fh>) {
                    $buffer .= $line;
                }
                close $fh;
                $self->parse($buffer);
            } else {
                $ua = new LWP::UserAgent;

                $req = new HTTP::Request GET => $arg;
                $res = $ua->request($req);

                if ($res->is_success) {
                    $self->parse($res->content);
                } else {
                    carp "Cannot import $arg";
                }
            }
        }
    }
}

=pod

=head2 parse

    $obj->parse STRING

"Parses" the weather product (contained in I<STRING>). Assumes I<STRING> is
a valid weather product (containing a valid WMO header line). This is used
by the I<import> method (and indirectly by I<new>).

=cut

sub parse {
    my $self = shift;
    my $product = shift;
    my $line,
       $level = 0;

    # allows us to update the same object

    my $this = $self->{$count}++;
    $self->{data}->{$this}->{text} = "";

    foreach $line (split /\n/, $product)
    {
        $line =~ s/\s+$//g;	# clean trailing spaces/carriage returns

        if ($level) {
            $self->{data}->{$this}->{text} .= $line."\n";
        }

        if (($level==0) and (Weather::WMO::valid($line)))
        {
            $self->{data}->{$this}->{WMO} = new Weather::WMO($line);
            if (defined($self->{WMO})) {
                unless ($self->{WMO}->cmp( $self->{data}->{$this}->{WMO})) {
                    croak "Cannot import different product types";
                }
            } else {
                $self->{WMO} = $self->{data}->{$this}->{WMO};
            }
            ++$level;

            $self->add($self->{WMO}->product, $this); # add text by WMO code
            $self->add($self->{WMO}->station, $this); # add text by station
        }
    }
    $self->purge();
}

sub add {
    my $self = shift;
    my ($name, $where) = @_;
    $self->{products}->{$name} = $where;
}

=pod

=head2 purge

    $obj->purge()

Purges "orphaned" weather products. In other words, garbage collection.

This will only occur when another weather product (presumably an updated one)
is imported into the object (using I<import> and I<parse>).


    $obj->purge LIST

Purges the weather products specified in LIST, if they exist. Orphaned
products will also be purged.

=cut

sub purge {
    my $self = shift;

    foreach (@_)
    {
        if (defined($self->{products}->{$_}))
        {
            undef $self->{products}->{$_};
        }
    }

    my @products = values %{$self->{products}},
       $ptr;
    foreach $ptr (keys %{$self->{data}}) {
        unless (grep /^$ptr$/, @products) {
            undef $self->{data}->{ptr};
        }
    }
}

=pod

=head2 pointer

    $obj->pointer PRODUCT, [FIELD]

This is an internal method for returning a "pointer" to a product (or to a
specified "field"). It is not meant to be used outside of this module.

Ah, but here's an excuse to attempt an explanation of the gory details....

Basically, all parsed products are stored in a hash called I<data>. Another
hash called I<products> contains pointers to the appropriate entry in I<data>.

While this structure may seem pointless (pun intended) for this module, it
is useful for the Weather::Product::NWS module, where some of the products
(AWIPS IDs and individual zones) are linked to substrings of data.

=cut

sub pointer { # given a product, it returns a pointer to that product
    my $self = shift;
    my $id = shift;

    my $field = shift;
    my $ptr;

    unless (defined($id)) {
        return undef;
    }
    $ptr = $self->{products}->{$id};

    if (defined($self->{data}->{$ptr}))
    {
        if (defined($field)) {
            return $self->{data}->{$ptr}->{$field};
        } else {
            return $self->{data}->{$ptr};
        }
    } else
    {
        return undef;
    }
}

=pod

=head2 products

    LIST = $obj->products;

Returns a list of available products (by name).

The definition of a "product" is a bit loose in this module. The WMO product
identifier (ie, "FPUS51" or "FPCN55") is added.

The reporting station (ie, "KNYC" or "CWNT") is also listed as a product
in cases where different stations may issue products with the same
identifier (such reports should really be handled with the
Weather::Product::NWS module and not this one).

=cut

sub products {
    my $self = shift;
    my @results = ();

    foreach (keys %{$self->{products}}) {
        if (defined($self->{products}->{$_})) {
            push @results, $_;
        }
    }
    return @results;
}

=pod

=head2 time

    TIME = $obj->time PRODUCT

For example,

    $time = localtime($forecast->time('FPUS81'));

Returns the timestamp of the parsed weather product.

Now a note about these timestamps: they are converted to Perl-friendly
time from the WMO header (using I<int_time>). WMO timestamps there are in
the form of DDHHMM, where DD is the day of the month, and HHMM is the time,
in UTC (we treat it as GMT here; the difference between the two is academic).

Why should you care? If for some strange reason you are parsing products
that are a month old, you'll get inaccurate timestamps.  Weather products
are not meant to be archived.

A future version of this module might attempt to fetch a "base time" from
local files or URLs.

=cut

sub time {
    my $self = shift;
    my $id = shift, $WMO;

    $WMO = $self->pointer($id, WMO);

    if (defined($WMO)) {
        return int_time($WMO->time);
    } else {
        return undef;
    }
}

=pod

=head2 int_time

    TIME = Weather::Product::int_time WMO_TIME, BASE

Attempts to convert WMO-style timestamps (found in WMO headers and UGC lines)
to something Perl-friendly. If no BASE is specified, the current time (I<time>)
is used.

=cut

sub int_time {
    my ($ugc_time, $base_time) = @_;

    unless (defined($base_time)) {
        $base_time = time;
    }

    my ($sec,$min,$hour,$mday,$mon,$year) = gmtime($base_time);

    $min  = substr($ugc_time, 4, 2)+0;  # we let timegm() do validating
    $hour = substr($ugc_time, 2, 2)+0;

    my $day = substr($ugc_time, 0, 2)+0;

    if (($day==1) and ($day<$mday)) {
        $mon++;
        if ($mon>11) {
            $year++;
            $mon = 0;
        }
    }
    return timegm(0,$min,$hour,$day,$mon,$year);
}

=pod

=head2 WMO

    WMO = $obj->WMO(PRODUCT)

Returns the WMO header of the specified product (as a Weather::WMO object).
For example,

    $WMO = $forecast->WMO('FPUS41');
    print "This forecast comes from station ", $WMO->station, "\n";

=head2 text

    $text = $obj->text(PRODUCT)

Perhaps the most important method. This returns the actual text of the
weather product. For example,


    print $forecast->text('FPUS41'), "\n";

=cut

sub AUTOLOAD {
    my $self = shift;
    my $type = ref($self)
                or croak "$self is not an object";

    my $name = $AUTOLOAD;
    $name =~ s/.*://;   # strip fully-qualified portion

    if (grep(/^$name$/,
        qw(WMO text)
    )) {
        if (@_) {
            return $self->pointer(@_, $name);
        } else {
            croak "Method `$name' requires arguments in class $type";
        }
    } else {
        croak "Can't access `$name' in class $type";
    }

}

1;

__END__

=pod

=head1 KNOWN BUGS

This version of the module does not (yet) handle addendums or multi-part
weather products.

Other issues with returning the I<time> of a product are explained above,
are are a limitation of the WMO header format, not this module.

=head1 SEE ALSO

Weather::WMO and Weather::Product::NWS.

=head1 DISCLAIMER

I am not a meteorologist nor am I associated with any weather service.
This module grew out of a hack which would fetch weather reports every
morning and send them to my pager. So I said to myself "Why not do this
the I<right> way..." and spent a bit of time surfing around the web
looking for documentation about this stuff....

=head1 AUTHOR

Robert Rothenberg <wlkngowl@unix.asb.com>

=cut

