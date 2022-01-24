use strict;
use warnings;
package Device::Chip::MCP3426;
use base 'Device::Chip';

use Carp;

# ABSTRACT: Device::Chip driver for the MCP3426 family of analog to digital converters
our $VERSION = 'v0.1.0';

use constant PROTOCOL => 'I2C';

sub I2C_options {
    my $self = shift;
    my %params = @_;

    my $addr = delete $params{addr} // 0x68;
    return (addr => $addr,
            max_bitrate => 400E3);
}

sub _send_config {
    my $self = shift;

    $self->{channel} //= 1;
    $self->{resolution} //= 12;
    $self->{gain} //= 1;

    my $config_reg = 0x10;

    $config_reg |= ($self->{channel} - 1) << 5;
    if ($self->{resolution} == 14)
    {
        $config_reg |= 0x4;
    } elsif ($self->{resolution} == 16)
    {
        $config_reg |= 0x8;
    }
    if ($self->{gain} == 2)
    {
        $config_reg |= 0x1;
    } elsif ($self->{gain} == 4)
    {
        $config_reg |= 0x2;
    } elsif ($self->{gain} == 8)
    {
        $config_reg |= 0x3;
    }

    $self->protocol->write(chr($config_reg));
}

sub set_channel {
    my ($self, $channel) = @_;

    $self->{channel} = $channel;
    $self->_send_config;
}

sub set_resolution {
    my ($self, $resolution) = @_;

    $self->{resolution} = $resolution;
    $self->_send_config;
}

sub set_gain {
    my ($self, $gain) = @_;

    $self->{gain} = $gain;
    $self->_send_config;
}

sub read_adc_voltage {
    my $self = shift;

    my $ready = 0;
    my $retries = 0;
    my @bytes;
    while ($ready == 0)
    {
        my $read_data = $self->protocol->read(3)->get();
        @bytes = unpack("C*", $read_data);
        $ready = ($bytes[2] & 0x80) == 0;
        if ($retries++ == 50)
        {
            carp "ADC Read timed out";
            return Future->done(undef);
        }
    }

    # unpack the unsigned 16-bit value
    my $read_value = $bytes[0] << 8 | $bytes[1];

    # convert two's complement to signed and multiply by voltage scale
    my $adc_value;
    if ($self->{resolution} == 16)
    {
        $adc_value = $read_value;
        $adc_value = 2**16 - $adc_value if ($adc_value & 0x8000);
        $adc_value *= 0.0000625;
    } elsif ($self->{resolution} == 14)
    {
        $adc_value = $read_value;
        $adc_value = 2**14 - $adc_value if ($adc_value & 0x2000);
        $adc_value *= 0.00025;
    } else
    {
        $adc_value = $read_value;
        $adc_value = 2**12 - $adc_value if ($adc_value & 0x800);
        $adc_value *= 0.001;
    }

    # multiply by PGA gain
    $adc_value /= $self->{gain};

    Future->done($adc_value);
}

1;
