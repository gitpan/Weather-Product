package Weather::Product;
require 5.004;
require Exporter;

use vars qw($VERSION);
$VERSION = "1.1.0";

@ISA = qw(Exporter);
@EXPORT = qw();
@EXPORT_OK = qw();

use Carp;
use FileHandle;
use LWP::UserAgent;
use Time::Local;

require Weather::WMO;

sub initialize {
    my $self = shift;

    $self->{count} = 0;			#
    $self->{products} = ();		# products parsed
    $self->{text} = ();			# text
    $self->{WMO} = undef;
}

sub new {
    my $this = shift;
    my $class = ref($this) || $this;
    my $self = {};
    bless $self, $class;
    $self->initialize;
    $self->import(@_);
    return $self;
}

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

  # To-do: remove old product if this is a new one, or process additional 
  # parts etc.

            $self->add($self->{WMO}->product, $this);
        }
    }
}

sub add {
    my $self = shift;
    my ($name, $where) = @_;
    $self->{products}->{$name} = $where;
}

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

sub int_time {
    my ($ugc_time, $base_time) = @_;
    unless (defined($base_time)) {
        $base_time = time;
    }

    my ($sec,$min,$hour,$mday,$mon,$year) = gmtime($base_time);

    $min  = substr($ugc_time, 4, 2)+0;
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

