package Business::CPI::Gateway::PagSeguro::ServerForm;
# ABSTRACT: Business::CPI's PagSeguro driver

use Moo;

use XML::LibXML;
use Carp;
use LWP::UserAgent;
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
        code => $self->get_checkout_code( $info )
    );
}

sub get_checkout_code {
    my ($self, $info) = @_;

    # XXX: should the encoding be parameterized?
    my $doc = XML::LibXML::Document->new( '1.0', 'UTF-8' );
    $doc->setStandalone(1);

    my $root = $doc->createElement('checkout');

    my $currency = $doc->createElement('currency');
    $currency->appendText($self->currency);

    my $payment_id = $doc->createElement('reference');
    $payment_id->appendText($info->{payment_id});

    my $sender = $doc->createElement('sender');

    my $sender_name = $doc->createElement('name');
    $sender_name->appendText($info->{buyer}->name);

    my $sender_email = $doc->createElement('email');
    $sender_email->appendText($info->{buyer}->email);

    $sender->appendChild($sender_name);
    $sender->appendChild($sender_email);

    my $shipping;
    my $buyer = $info->{buyer};
    if ($buyer->address_street) {
        $shipping = $doc->createElement('shipping');
        my $address = $doc->createElement('address');

        my $street = $doc->createElement('street');
        $street->appendText($buyer->address_street);

        my $number = $doc->createElement('number');
        $number->appendText($buyer->address_number);

        my $complement = $doc->createElement('complement');
        $complement->appendText($buyer->address_complement);

        my $district = $doc->createElement('district');
        $district->appendText($buyer->address_district);

        my $postal_code = $doc->createElement('postalCode');
        $postal_code->appendText($buyer->address_zip_code);

        my $city = $doc->createElement('city');
        $city->appendText($buyer->address_city);

        my $state = $doc->createElement('state');
        $state->appendText($buyer->address_state);

        my $country = $doc->createElement('country');
        $country->appendText(
            uc( Locale::Country::country_code2code( $buyer->address_country ) )
        );

        $address->appendChild($street);
        $address->appendChild($number);
        $address->appendChild($complement);
        $address->appendChild($district);
        $address->appendChild($postal_code);
        $address->appendChild($city);
        $address->appendChild($state);
        $address->appendChild($country);

        $shipping->appendChild($address);
    }

    my $cart = $info->{cart};
    my $handling = $cart->handling || 0;
    my $discount = $cart->discount || 0;
    my $tax      = $cart->tax      || 0;

    my $extra_amount = $tax + $handling - $discount;
    my $ea;

    if ($extra_amount) {
        $ea = $doc->createElement('extraAmount');
        $ea->appendText($extra_amount);
    }

    my $items = $doc->createElement('items');

    for my $i (@{ $info->{items} }) {
        my $item = $doc->createElement('item');

        my $id = $doc->createElement('id');
        $id->appendText($i->id);

        my $desc = $doc->createElement('description');
        $desc->appendText($i->description);

        my $amount = $doc->createElement('amount');
        $amount->appendText($i->price);

        my $qty = $doc->createElement('quantity');
        $qty->appendText($i->quantity);

        my $weight = $doc->createElement('weight');
        $weight->appendText($i->weight) if $i->weight;

        my $shipping = $doc->createElement('shippingCost');
        $shipping->appendText($i->shipping) if $i->shipping;

        $item->appendChild($id);
        $item->appendChild($desc);
        $item->appendChild($amount);
        $item->appendChild($qty);
        $item->appendChild($weight) if $i->weight;
        $item->appendChild($shipping) if $i->shipping;

        $items->appendChild($item);
    }

    $root->appendChild($currency);
    $root->appendChild($items);
    $root->appendChild($payment_id);
    $root->appendChild($sender);
    $root->appendChild($shipping) if $shipping;
    $root->appendChild($ea) if $ea;

    $doc->setDocumentElement($root);

    my $ua = LWP::UserAgent->new;

    my $req = $ua->post(
        $self->base_url . '/checkout?email=' .
            $self->receiver_email . '&token=' .$self->token,
        Content_Type => 'application/xml; charset=UTF-8',

        Content      => $doc->toString,

    );

    die $req->status_line . "\n\n" . $req->decoded_content unless ($req->is_success);

    return XML::LibXML->load_xml(
        string => $req->decoded_content
    )->firstChild()->getChildrenByTagName('code')->string_value;
}

1;

