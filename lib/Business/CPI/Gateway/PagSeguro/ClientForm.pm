package Business::CPI::Gateway::PagSeguro::ClientForm;
# ABSTRACT: Business::CPI's PagSeguro driver

use Moo;

use XML::LibXML;
use Carp;
use LWP::Simple ();
use URI;
use URI::QueryParam;
use DateTime;
use Locale::Country ();
use Data::Dumper;

extends 'Business::CPI::Gateway::PagSeguro';




sub _checkout_form_main_map {
    return {
        receiver_email => 'receiverEmail',
        currency       => 'currency',
        form_encoding  => 'encoding',
    };
}

sub _checkout_form_item_map {
    my ($self, $number) = @_;

    return {
        id          => "itemId$number",
        description => "itemDescription$number",
        price       => "itemAmount$number",
        quantity    => "itemQuantity$number",
        weight      => {
            name   => "itemWeight$number",
            coerce => sub { $_[0] * 1000 },
        },
        shipping    => "itemShippingCost$number"
    };
}

sub _checkout_form_buyer_map {
    return {
        name               => 'senderName',
        email              => 'senderEmail',
        address_complement => 'shippingAddressComplement',
        address_district   => 'shippingAddressDistrict',
        address_street     => 'shippingAddressStreet',
        address_number     => 'shippingAddressNumber',
        address_city       => 'shippingAddressCity',
        address_state      => 'shippingAddressState',
        address_zip_code   => 'shippingAddressPostalCode',
        address_country    => {
            name => 'shippingAddressCountry',
            coerce => sub {
                uc(
                    Locale::Country::country_code2code(
                        $_[0], 'alpha-2', 'alpha-3'
                    )
                )
            },
        },
    };
}

sub _get_hidden_inputs_for_cart {
    my ($self, $cart) = @_;

    my $handling = $cart->handling || 0;
    my $discount = $cart->discount || 0;
    my $tax      = $cart->tax      || 0;

    my $extra_amount = $tax + $handling - $discount;

    if ($extra_amount) {
        return ( extraAmount => sprintf( "%.2f", $extra_amount ) );
    }
    return ();
}

sub get_hidden_inputs {
    my ($self, $info) = @_;

    return (
        reference => $info->{payment_id},

        $self->_get_hidden_inputs_main(),
        $self->_get_hidden_inputs_for_buyer($info->{buyer}),
        $self->_get_hidden_inputs_for_items($info->{items}),
        $self->_get_hidden_inputs_for_cart($info->{cart}),
    );
}

1;


