#!/usr/bin/env perl

use strict;
use warnings;

use JSON qw(decode_json);
use LWP::UserAgent;
use HTTP::Request;
use Readonly;
use Digest::SHA qw(hmac_sha256_base64);

use buzzfeed2::Mailer;
use buzzfeed2::Service::Buzzes;

Readonly my $Stats_days => 7;
Readonly my $Stats_seconds_in_day => 60 * 60 * 24;

Readonly my $USER_ID      => "35268251634888";

my $addressees = [
  'karen.nolastname@buzzfeed.com',
  'whitney.nolastname@buzzfeed.com',
  'ryan.nolastname@buzzfeed.com',
  'wolly.nolastname@buzzfeed.com'
];

sub get_buzzes {
  my $buzzes_service = buzzfeed2::Service->get_service( 'Buzzes', { api_version => 2 } );
  my $buzzes_resp = $buzzes_service->get( { user_id => $USER_ID } );

  throw buzzfeed2::error::FileNotFound("BuzzesError: $buzzes_resp->{error}")
    unless ( $buzzes_resp->{success} && $buzzes_resp->{buzzes} );

  my $buzzes = check_published($buzzes_resp);

  return $buzzes;
}

sub check_published {
  my ($resp) = @_;
  my $timestamp = time;
  my $stats_since_date = $timestamp - ($Stats_days * $Stats_seconds_in_day);
  my @buzzes;

  foreach my $buzz ( @{ $resp->{buzzes} } ) {
    if($buzz->{published} >= $stats_since_date) {
      push @buzzes, $buzz;
    }
  }

  return { buzzes => \@buzzes };
}

sub get_votes {
  my ($id) = @_;

  my $ua = LWP::UserAgent->new();
  my $result = $ua->get( "http://mango.buzzfeed.com/polls/service/aggregate/editorial/get/?poll_id=" . $id );

  my $parsed_data = decode_json $result->decoded_content;

  my $votes = {
    "fab" => 0,
    "drab" => 0,
    "error" => 0
  };

  if($parsed_data->{success} == 1) {
    $votes->{fab} = $parsed_data->{data}->{results}->{143};
    $votes->{drab} = $parsed_data->{data}->{results}->{144};
  } else {
    $votes->{error} = 1;
  }

  return $votes;
}

sub create_table_row {
  my ($url, $title, $votes) = @_;

  my $table_row = qq^
  <tr>
    <td><a href="$url">$title</a></td>
    <td>$votes</td>
  </tr>
^;

  return $table_row;
}

sub create_table_header {
  my ($title) = @_;
  my $table_header = qq^
  <tr>
    <td colspan="2">$title<td>
  </tr>
^;

  return $table_header;
}

sub create_table {
  my ($title, $table_data, $type) = @_;

  my $table = "<table style=\"padding-bottom: 15px;\">";
  $table .= create_table_header($title);
  foreach my $table_row (@{$table_data}) {
    my $count_value = $table_row->{drab};
    $count_value = $table_row->{fab} if $type eq "fab";
    $table .= create_table_row("http://www.buzzfeed.com/fabordrabfeed/" . $table_row->{uri}, $table_row->{title}, $count_value);
  }
  $table .= "</table>"
}

sub main {
  my ( $self ) = @_;
  # query data from buzz api and parse the json
  my $data = get_buzzes();
  my @buzz_list;

  # check fab count and drab count for each items received above
  foreach my $buzz ( @{ $data->{buzzes} } ) {
    my $vote_data = get_votes($buzz->{id});

    my $buzz_data = {
      "id"    => $buzz->{id},
      "uri"   => $buzz->{uri},
      "title" => $buzz->{title},
      "fab"   => $vote_data->{fab},
      "drab"  => $vote_data->{drab}
    };

    push @buzz_list, $buzz_data if $vote_data->{error} == 0;
  }

  # sort the list by fab and drab descending
  my @fab_sorted  = sort { $b->{fab}  <=> $a->{fab}  } @buzz_list;
  my @drab_sorted = sort { $b->{drab} <=> $a->{drab} } @buzz_list;

  # limit to 50 items
  @fab_sorted  = splice @fab_sorted, 0, 50;
  @drab_sorted = splice @drab_sorted, 0, 50;

  my $fab_table  = create_table("Fab",  \@fab_sorted,  "fab" );
  my $drab_table = create_table("Drab", \@drab_sorted, "drab");

  buzzfeed2::Mailer->send_html({
    to      => $addressees,
    from    => buzzfeed2::Config->DEFAULT_INBOUND_EMAIL,
    subject => 'Top 50 Fab posts',
    message => $fab_table,
  });

  buzzfeed2::Mailer->send_html({
    to      => $addressees,
    from    => buzzfeed2::Config->DEFAULT_INBOUND_EMAIL,
    subject => 'Top 50 Drab posts',
    message => $drab_table,
  });
}

main();
