package Catmandu::Store::ElasticSearch;

use Catmandu::Sane;

our $VERSION = '0.0506';

use Moo;
use Search::Elasticsearch;
use Catmandu::Store::ElasticSearch::Bag;
use namespace::clean;

with 'Catmandu::Store';
with 'Catmandu::Droppable';

has index_name => (is => 'ro', required => 1);
has index_settings => (is => 'ro', lazy => 1, default => sub { +{} });
has index_mappings => (is => 'ro', lazy => 1, default => sub { +{} });
has _es_args => (is => 'rw', lazy => 1, default => sub { +{} });
has es => (is => 'lazy');

sub _build_es {
    my ($self) = @_;
    my $es = Search::Elasticsearch->new($self->_es_args);
    unless ($es->indices->exists(index => $self->index_name)) {
        $es->indices->create(
            index => $self->index_name,
            body  => {
                settings => $self->index_settings,
                mappings => $self->index_mappings,
            },
        );
    }
    $es;
}

sub BUILD {
    my ($self, $args) = @_;
    $self->_es_args($args);
}

sub drop {
    my ($self) = @_;
    $self->es->indices->delete(index => $self->index_name);
}

1;

__END__

=pod

=head1 NAME

Catmandu::Store::ElasticSearch - A searchable store backed by Elasticsearch

=head1 SYNOPSIS

    # From the command line

    # Import data into ElasticSearch
    $ catmandu import JSON to ElasticSearch --index-name 'catmandu' < data.json

    # Export data from ElasticSearch
    $ catmandu export ElasticSearch --index-name 'catmandu' to JSON > data.json

    # Export only one record
    $ catmandu export ElasticSearch --index-name 'catmandu' --id 1234

    # Export using an ElasticSearch query
    $ catmandu export ElasticSearch --index-name 'catmandu' --query "name:Recruitment OR name:college"

    # Export using a CQL query (needs a CQL mapping)
    $ catmandu export ElasticSearch --index-name 'catmandu' --q "name any college"

    # From Perl

    use Catmandu;

    my $store = Catmandu->store('ElasticSearch', index_name => 'catmandu');

    my $obj1 = $store->bag->add({ name => 'Patrick' });

    printf "obj1 stored as %s\n" , $obj1->{_id};

    # Force an id in the store
    my $obj2 = $store->bag->add({ _id => 'test123' , name => 'Nicolas' });

    # Commit all changes
    $store->bag->commit;

    $store->bag->delete('test123');

    $store->bag->delete_all;

    # All bags are iterators
    $store->bag->each(sub { ... });
    $store->bag->take(10)->each(sub { ... });

    # Query the store using a simple ElasticSearch query
    my $hits = $store->bag->search(query => '(content:this OR name:this) AND (content:that OR name:that)');

    # Native queries are also supported by providing a hash of terms
    # See the ElasticSearch manual for more examples
    my $hits = $store->bag->search(
        query => {
            # All name.exact fields that start with 'test'
            prefix => {
                'name.exact' => 'test'
            }
        } ,
        limit => 1000);

    # Catmandu::Store::ElasticSearch supports CQL...
    my $hits = $store->bag->search(cql_query => 'name any "Patrick"');

=head1 METHODS

=head2 new(index_name => $name, [...])

=head2 new(index_name => $name , index_mapping => \%map, [...])

=head2 new(index_name => $name , ... , bags => { data => { cql_mapping => \%map } })

Create a new Catmandu::Store::ElasticSearch store connected to index $name.
Optional extra ElasticSearch connection parameters will be passed on to the
backend database.

Optionally provide an C<index_mapping> which contains a ElasticSearch schema
for each field in the index (See below).

Optionally provide for each bag a C<cql_mapping> to map fields to CQL indexes.

=head2 drop

Deletes the Elasticsearch index backing this store. Calling functions after
this may fail until this class is reinstantiated, creating a new index.

=head1 INDEX MAP

The index_mapping contains a Elasticsearch schema mappings for each
bag defined in the index. E.g.

    {
        data => {
            properties => {
                _id => {
                    type           => 'string',
                    include_in_all => 'true',
                    index          => not_analyzed
                } ,
                title => {
                    type           => 'string'
                }
            }
        }
    }

In the example above the default 'data' bag of the ElasticSearch contains
an '_id' field of type 'string' which is stored automatically also in the
'_all' search field. The '_id' is not analyzed. The bag also contains a 'title'
field of type string.

See L<https://www.elastic.co/guide/en/elasticsearch/reference/2.2/mapping.html>
for more information on mappings.

These mappings can be passed inside a Perl program, or be written into a
Catmandu 'catmandu.yml' configuration file. E.g.

   # catmandu.yml
   store:
       search:
          package: ElasticSearch
          options:
            index_name: catmandu
            index_mappings
              data:
                properties:
                    _id:
                        type: string
                        include_in_all: true
                        index: not_analyzed
                    title:
                        type: string

Via the command line these configuration parameters can be read in by using the
name of the store, C<search> in this case:

   $ catmandu import JSON to search < data.json
   $ catmandu export search to JSON > data.json

=head1 CQL MAP

Catmandu::Store::ElasticSearch supports CQL searches when a cql_mapping is provided
for each bag. This hash contains a translation of CQL fields into Elasticsearch
searchable fields.

 # Example mapping
  {
    indexes => {
      title => {
        op => {
          'any'   => 1 ,
          'all'   => 1 ,
          '='     => 1 ,
          '<>'    => 1 ,
          'exact' => {field => [qw(mytitle.exact myalttitle.exact)]}
        } ,
        field => 'mytitle',
        sort  => 1,
        cb    => ['Biblio::Search', 'normalize_title']
      }
    }
 }

The CQL mapping above will support for the 'title' field the CQL operators:
any, all, =, <> and exact.

The 'title' field will be mapping into the Elasticsearch field 'mytitle', except
for the 'exact' operator. In case of 'exact' we will search both the
'mytitle.exact' and 'myalttitle.exact' fields.

The CQL mapping allows for sorting on the 'title' field. If, for instance, we
would like to use a special ElasticSearch field for sorting we could
have written "sort => { field => 'mytitle.sort' }".

The callback field C<cb> contains a reference to subroutines to rewrite or
augment a search query. In this case, the Biblio::Search package contains a
normalize_title subroutine which returns a string or an ARRAY of strings
with augmented title(s). E.g.

    package Biblio::Search;

    sub normalize_title {
       my ($self,$title) = @_;
       my $new_title =~ s{[^A-Z0-9]+}{}g;
       $new_title;
    }

    1;

Also this configuration can be added to a catmandu.yml configuration file like:

    # catmandu.yml
    store:
        search:
           package: ElasticSearch
           options:
             index_name: catmandu
             index_mappings
               data:
                 properties:
                     _id:
                         type: string
                         include_in_all: true
                         index: not_analyzed
                     title:
                         type: string
             bags:
               data:
                  cql_mapping:
                    indexes:
                        title:
                            op:
                                'any': true
                                'all': true
                                '=':   true
                                '<>':  true
                                'exact':
                                    field: [ 'mytitle.exact' , 'myalttitle.exact' ]
                            field: mytitle
                            sort: true
                            cb: [ 'Biblio::Search' , 'normalize_title' ]
                    }

Via the command line these configuration parameters can be read in by using the
name of the store, C<search> in this case:

   $ catmandu export search -q 'title any blablabla' to JSON > data.json

=head1 COMPATIBILITY

This store expects version 1.0 or higher of the Elasticsearch server.

Note that Elasticsearch >= 2.0 doesn't allow keys that start with an underscore such as
C<_id>. You can use the C<key_prefix> option at store level or C<id_prefix> at
bag level to handle this.

    # in your catmandu.yml
    store:
      yourstore:
        package: ElasticSearch
        options:
          # use my_id instead of _id
          key_prefix: my_

If you want to use the C<delete_by_query> method with Elasticsearch >= 2.0 you
need have to L<install the delete by query plugin|https://www.elastic.co/guide/en/elasticsearch/plugins/current/plugins-delete-by-query.html>.

=head1 MIGRATING A STORE FROM ELASTICSEARCH 1.0 TO 2.0 OR HIGHER

1. backup your data as JSON

    catmandu export yourstore --bag yourbag to --file /path/to/yourbag.json -v

2. drop the store

    catmandu drop yourstore

3. upgrade the Elasticsearch server

4. update your catmandu.yml with a C<key_prefix> or C<id_prefix> (see COMPATIBILITY)

5. import your data using the new keys specified in your catmandu.yml

    catmandu import --file /path/to/yourbag.json --fix 'move_field(_id, my_id)' \
    to yourstore --bag yourbag -v

=head1 ERROR HANDLING

Error handling can be activated by specifying an error handling callback for index when creating
a store. E.g. to create an error handler for the bag 'data' index use:

    my $store = Catmandu::Store::ElasticSearch->new(
                    index_name => 'catmandu'
                    bags => { data => { on_error => \&error_handler } }
                 });

    sub error_handler {
        my ($action, $response, $i) = @_;
    }

=head1 SEE ALSO

L<Catmandu::Store>

=head1 AUTHOR

Nicolas Steenlant, C<< <nicolas.steenlant at ugent.be> >>

=head1 CONTRIBUTORS

=over 4

=item Dave Sherohman, C<< dave.sherohman at ub.lu.se >>

=item Robin Sheat, C<< robin at kallisti.net.nz >>

=item Patrick Hochstenbach, C<< patrick.hochstenbach at ugent.be >>

=back

=head1 LICENSE AND COPYRIGHT

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.

=cut
