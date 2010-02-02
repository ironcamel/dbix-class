package DBIx::Class::Storage::DBI::SQLAnywhere;

use strict;
use warnings;
use base qw/DBIx::Class::Storage::DBI/;
use mro 'c3';
use List::Util ();

__PACKAGE__->mk_group_accessors(simple => qw/
  _identity
/);

=head1 NAME

DBIx::Class::Storage::DBI::SQLAnywhere - Driver for Sybase SQL Anywhere

=head1 DESCRIPTION

This class implements autoincrements for Sybase SQL Anywhere, selects the
RowNumberOver limit implementation and provides
L<DBIx::Class::InflateColumn::DateTime> support.

You need the C<DBD::SQLAnywhere> driver that comes with the SQL Anywhere
distribution, B<NOT> the one on CPAN. It is usually under a path such as:

  /opt/sqlanywhere11/sdk/perl

Recommended L<DBIx::Class::Storage::DBI/connect_info> settings:

  on_connect_call => 'datetime_setup'

=head1 METHODS

=cut

sub last_insert_id { shift->_identity }

sub insert {
  my $self = shift;
  my ($source, $to_insert) = @_;

  my $supplied_col_info = $self->_resolve_column_info($source, [keys %$to_insert]);

  my $is_identity_insert = (List::Util::first { $_->{is_auto_increment} } (values %$supplied_col_info) )
     ? 1
     : 0;

  my $identity_col = List::Util::first {
      $source->column_info($_)->{is_auto_increment} 
  } $source->columns;

  if ((not $is_identity_insert) && $identity_col) {
    my $dbh = $self->_get_dbh;
    my $table_name = $source->from;
    $table_name    = $$table_name if ref $table_name;

    my ($identity) = $dbh->selectrow_array("SELECT GET_IDENTITY('$table_name')");

    $to_insert->{$identity_col} = $identity;

    $self->_identity($identity);
  }

  return $self->next::method(@_);
}

# this sub stolen from DB2

sub _sql_maker_opts {
  my ( $self, $opts ) = @_;

  if ( $opts ) {
    $self->{_sql_maker_opts} = { %$opts };
  }

  return { limit_dialect => 'RowNumberOver', %{$self->{_sql_maker_opts}||{}} };
}

# this sub stolen from MSSQL

sub build_datetime_parser {
  my $self = shift;
  my $type = "DateTime::Format::Strptime";
  eval "use ${type}";
  $self->throw_exception("Couldn't load ${type}: $@") if $@;
  return $type->new( pattern => '%Y-%m-%d %H:%M:%S.%6N' );
}

=head2 connect_call_datetime_setup

Used as:

    on_connect_call => 'datetime_setup'

In L<DBIx::Class::Storage::DBI/connect_info> to set the date and timestamp
formats (as temporary options for the session) for use with
L<DBIx::Class::InflateColumn::DateTime>.

The C<TIMESTAMP> data type supports up to 6 digits after the decimal point for
second precision. The full precision is used.

The C<DATE> data type supposedly stores hours and minutes too, according to the
documentation, but I could not get that to work. It seems to only store the
date.

You will need the L<DateTime::Format::Strptime> module for inflation to work.

=cut

sub connect_call_datetime_setup {
  my $self = shift;

  $self->_do_query(
    "set temporary option timestamp_format = 'yyyy-mm-dd hh:mm:ss.ssssss'"
  );
  $self->_do_query(
    "set temporary option date_format      = 'yyyy-mm-dd hh:mm:ss.ssssss'"
  );
}

1;

=head1 AUTHOR

See L<DBIx::Class/AUTHOR> and L<DBIx::Class/CONTRIBUTORS>.

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut