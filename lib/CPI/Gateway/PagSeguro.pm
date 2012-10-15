package CPI::Gateway::PagSeguro;
# ABSTRACT: CPI's PagSeguro driver

use Moo;
use XML::LibXML;
use Carp;
use LWP::Simple ();
use URI;
use URI::QueryParam;
use DateTime;

extends 'CPI::Gateway::Base';

has '+checkout_url' => (
    default => sub { 'https://pagseguro.uol.com.br/v2/checkout/payment.html' },
);

has '+currency' => (
    default => sub { 'BRL' },
);

has base_url => (
    is => 'ro',
    default => sub { 'https://ws.pagseguro.uol.com.br/v2' },
);

has token => (
    is  => 'ro',
);

sub get_notifications_url {
    my ($self, $code) = @_;

    return $self->_build_uri("/transactions/notifications/$code");
}

sub get_transaction_details_url {
    my ($self, $code) = @_;

    return $self->_build_uri("/transactions/$code");
}

sub get_transaction_query_url {
    my ($self, $info) = @_;

    $info ||= {};

    my $final_date   = $info->{final_date}   || DateTime->now(time_zone => 'local'); # XXX: really local?
    my $initial_date = $info->{initial_date} || $final_date->clone->subtract(days => 30);

    my $new_info = {
        initialDate    => $initial_date->strftime('%Y-%m-%dT%H:%M'),
        finalDate      => $final_date->strftime('%Y-%m-%dT%H:%M'),
        page           => $info->{page} || 1,
        maxPageResults => $info->{rows} || 1000,
    };

    return $self->_build_uri('/transactions', $new_info);
}

sub query_transactions { goto \&get_and_parse_transactions }

sub get_and_parse_notification {
    my ($self, $code) = @_;

    my $xml = $self->_load_xml_from_url(
        $self->get_notifications_url($code)
    );

    return $self->_parse_transaction($xml);
}

sub notify {
    my ($self, $req) = @_;

    if ($req->params->{notificationType} eq 'transaction') {
        return $self->get_and_parse_notification(
            $req->params->{notificationCode}
        );
    }
}

sub get_and_parse_transactions {
    my ($self, $info) = @_;

    my $xml = $self->_load_xml_from_url(
        $self->get_transaction_query_url( $info )
    );

    my @transactions = $xml->getChildrenByTagName('transactions')->get_node(1)->getChildrenByTagName('transaction');

    return {
        current_page         => $xml->getChildrenByTagName('currentPage')->string_value,
        results_in_this_page => $xml->getChildrenByTagName('resultsInThisPage')->string_value,
        total_pages          => $xml->getChildrenByTagName('totalPages')->string_value,
        transactions         => [
            map { $self->get_transaction_details( $_ ) }
            map { $_->getChildrenByTagName('code')->string_value } @transactions
        ],
    };
}

sub get_transaction_details {
    my ($self, $code) = @_;

    my $xml = $self->_load_xml_from_url(
        $self->get_transaction_details_url( $code )
    );

    my $result = $self->_parse_transaction($xml);
    $result->{buyer_email} = $xml->getChildrenByTagName('sender')->get_node(1)->getChildrenByTagName('email')->string_value;

    return $result;
}

sub _parse_transaction {
    my ($self, $xml) = @_;

    my $date   = $xml->getChildrenByTagName('date')->string_value;
    my $ref    = $xml->getChildrenByTagName('reference')->string_value;
    my $status = $xml->getChildrenByTagName('status')->string_value;
    my $amount = $xml->getChildrenByTagName('grossAmount')->string_value;

    return {
        payment_id => $ref,
        status     => $self->_status_code_map($status),
        amount     => $amount,
        date       => $date,
    };
}

sub _load_xml_from_url {
    my ($self, $url) = @_;

    return XML::LibXML->load_xml(
        string => LWP::Simple::get( $url )
    )->firstChild();
}

sub _build_uri {
    my ($self, $path, $info) = @_;

    $info ||= {};

    $info->{email} = $self->receiver_email;
    $info->{token} = $self->token;

    my $uri = URI->new($self->base_url . $path);

    while (my ($k, $v) = each %$info) {
        $uri->query_param($k, $v);
    }

    return $uri->as_string;
}

sub _status_code_map {
    my ($self, $status) = @_;

    croak qq/No status provided/
        unless $status;

    $status = int($status);

    my @status_codes;
    @status_codes[1,2,5] = ('processing') x 3;
    @status_codes[6,7]   = ('failed') x 2;
    @status_codes[3,4]   = ('completed') x 2;

    croak qq/Can't understand status code $status/
        if ($status > 7 || $status < 1);

    return $status_codes[$status];
}

sub get_hidden_inputs {
    my ($self, $info) = @_;

    my @hidden_inputs = (
        receiverEmail => $self->receiver_email,
        currency      => $self->currency,
        encoding      => $self->form_encoding,
        reference     => $info->{payment_id},
        senderName    => $info->{buyer}->name,
        senderEmail   => $info->{buyer}->email,
    );

    my $i = 1;

    foreach my $item (@{ $info->{items} }) {
        push @hidden_inputs,
          (
            "itemId$i"          => $item->id,
            "itemDescription$i" => $item->description,
            "itemAmount$i"      => $item->price,
            "itemQuantity$i"    => $item->quantity,
          );
        $i++;
    }

    return @hidden_inputs;
}

1;

=attr token

The token provided by PagSeguro

=attr base_url

The url for PagSeguro API. Not to be confused with the checkout url, this is
just for the API.

=method get_notifications_url

Reader for the notifications URL in PagSeguro's API. This uses the base_url
attribute.

=method get_transaction_details_url

Reader for the transaction details URL in PagSeguro's API. This uses the
base_url attribute.

=method get_transaction_query_url

Reader for the transaction query URL in PagSeguro's API. This uses the base_url
attribute.

=method get_and_parse_notification

Gets the url from L</get_notifications_url>, and loads the XML from there.
Returns a parsed standard CPI hash.

=method get_and_parse_transactions

=method get_transaction_details

=method query_transactions

Alias for L</get_and_parse_transactions> to maintain compatibility with other
CPI modules.

=method notify

=method get_hidden_inputs

=head1 SEE ALSO

L<CPI::Gateway::Base>
