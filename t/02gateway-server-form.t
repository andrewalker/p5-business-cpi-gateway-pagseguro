#!/usr/bin/env perl
use utf8;
use warnings;
use strict;
use Test::More;
use FindBin '$Bin';
use Business::CPI::Gateway::PagSeguro::ServerForm;
use Encode;
unless ( $ENV{'RECEIVER_EMAIL'} and $ENV{'TOKEN'} ) {
    plan skip_all => 'You need setup ENV RECEIVER_EMAIL AND TOKEN';
}


sub get_value_for {
    my ($form, $name) = @_;
    return $form->look_down(_tag => 'input', name => $name )->attr('value');
}

ok(my $cpi = Business::CPI::Gateway::PagSeguro::ServerForm->new(
    receiver_email => $ENV{RECEIVER_EMAIL},
    token          => $ENV{TOKEN},
), 'build $cpi');

isa_ok($cpi, 'Business::CPI::Gateway::PagSeguro');

ok(my $cart = $cpi->new_cart({
    buyer => {
        name  => 'Mr. Buyer',
        email => 'sender@andrewalker.net',


    }
}), 'build $cart');

isa_ok($cart, 'Business::CPI::Cart');

ok(my $item = $cart->add_item({
    id          => 1,
    quantity    => 1,
    price       => 200,
    description => 'my desc',
}), 'build $item');

ok(my $form = $cart->get_form_to_pay(123), 'get form to pay');
isa_ok($form, 'HTML::Element');

like(get_value_for($form, 'code'), qr/^.{32}$/, 'valid code');



ok($item = $cart->add_item({
    id          => 1,
    quantity    => 0,
    price       => 200,
    description => 'my desc',
}), 'build $item');


eval {
    ok($form = $cart->get_form_to_pay(123), 'get form to pay');
    isa_ok($form, 'HTML::Element');
};
like($@, qr/Item quantity out of range/, 'Item quantity out of range');

done_testing;
