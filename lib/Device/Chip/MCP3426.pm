use strict;
use warnings;
package Device::Chip::MCP3426;
use base 'Device::Chip';

use Carp;

# ABSTRACT: Device::Chip driver for the MCP3426 family of analog to digital converters
our $VERSION = 'v0.1.0';

use constant PROTOCOL => 'I2C';

=head1 NAME

C<Device::Chip::MCP3426> - chip driver for MCP3426 family analog to
digital converters

=head1 SYNOPSIS

    use Device::Chip::MCP3426;

    my $chip = Device::Chip::MCP3426->new();
    $chip->mount( ... )->get();

    $chip->set_resolution(16);
    $chip->set_gain(1);
    $chip->set_channel(1);

    my $voltage = $chip->read_adc_voltage;

=head1 DESCRIPTION

This class communicates with the MCP3426 family of analog to digital
converters, including the MCP3427 and MCP3428.

=cut

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

=head1 METHODS

=head2 set_channel($channel)

Set the input channel to read. For the MCP2426 and MCP3427 this can be
1 or 2; for the MCP3428 it can also be 3 or 4.

=cut

sub set_channel {
    my ($self, $channel) = @_;

    $self->{channel} = $channel;
    $self->_send_config;
}

=head2 set_resolution($resolution)

Set the digitizing resolution in bits to 12, 14, or 16.

=cut

sub set_resolution {
    my ($self, $resolution) = @_;

    $self->{resolution} = $resolution;
    $self->_send_config;
}

=head2 set_gain($gain)

Set the PGA gain to 1, 2, 4, or 8.

=cut

sub set_gain {
    my ($self, $gain) = @_;

    $self->{gain} = $gain;
    $self->_send_config;
}

=head2

Read the analog voltage on the selected channel and return the result
in volts. This method will poll the ready bit until a new conversion
is available before returning, or return C<undef> if no result is
available after polling 50 times.

=cut

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

=head1 AUTHOR

Stephen Cavilia E<lt>sac@atomicradi.usE<gt>

=head1 COPYRIGHT

Copyright 2022 Stephen Cavilia

This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut

1;
