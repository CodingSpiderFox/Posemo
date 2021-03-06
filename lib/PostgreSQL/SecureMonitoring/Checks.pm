package PostgreSQL::SecureMonitoring::Checks;

=head1 NAME

 PostgreSQL::SecureMonitoring::Checks -- base class for all Posemo checks

=head1 SYNOPSIS

The following example doesn't use the sugar from L<PostgreSQL::SecureMonitoring::ChecksHelper|PostgreSQL::SecureMonitoring::ChecksHelper>.

 package PostgreSQL::SecureMonitoring::Checks::SimpleAlive;  # by Default, the name of the check is build from this package name
 
 use Moose;                                                  # This is a Moose class ...
 extends "PostgreSQL::SecureMonitoring::Checks";             # ... which extends our base check class
 
 sub _build_sql { return "SELECT true;"; }                   # this sub simply returns the SQL for the check
 
 1;                                                          # every Perl module must return (end with) a true value


=head1 DESCRIPTION

  TODO: more Documentation!
  TODO: Separate install methods into their own module?


This is the base class for all Posemo checks. It declares all base methods for 
creating SQL in initialisation, calling the check at runtime etc.

The above minimalistic example SimpleAlive creates the following SQL function:

  CREATE OR REPLACE FUNCTION simple_alive() 
    RETURNS  boolean 
    AS
    
    $code$
      SELECT true;
    $code$
    
    LANGUAGE sql
    STABLE
    SECURITY DEFINER
    SET search_path = monitoring, pg_temp;
  
  ALTER FUNCTION simple_alive OWNER TO posemo_admin;
  REVOKE ALL     ON FUNCTION simple_alive() FROM PUBLIC;
  GRANT  EXECUTE ON FUNCTION simple_alive() TO posemo;
  

At runtime it is called with this SQL:

  SELECT * FROM my_check();
  


=head2 results


There may be a lot of different ways for check modules to deliver their results.

There may be one result, e.g. true/false or a single number (e.g. number of backends), 
or multiple values for e.g. multiple databases



If there are more then one database which delivers inforations in one check, it 
should report the database in the first column:



    database    | active | idle | idle in transaction | idle in transaction (aborted) | fastpath function call | disabled 
 ---------------+--------+------+---------------------+-------------------------------+------------------------+----------
  !TOTAL        |      1 |    0 |                   0 |                             0 |                      0 |        0
  _posemo_tests |      1 |    0 |                   0 |                             0 |                      0 |        0
  postgres      |      0 |    0 |                   0 |                             0 |                      0 |        0
 (3 rows)


Types of results:

 * Single value: scalar

 * Multiple single values: Array of scalars

 * Multiple rows with multiple values: array of arrayrefs

Structure for output/result:

   [
      {
      host => "hostname",
      results => 
         [
            {
            check       => "check_name",
            result      => [ {}, {}, ... ],
            result_type => "",   # multiline, single, list
            columns     => [qw(database total active idle), "idle in transaction", "other", ],
            critical    => 0,    # or 1
            warning     => 0,    # or 1
            message     => "",   # warn/crit message or empty
            error       => "",   # error message, e.g. when can't run the check
            },
         ],
      },
     
   ]



Simple results: one value.


More complex: 








This check would give 5 results; ouput modules should use the databse in the check name and 
each value in the performance data



=head2 TODO
???
TODO: SQL schema handling; 
should be: default empty and user should have an search_path? (to "monitorin")???



=cut


use Moose;
use namespace::autoclean;

use Scalar::Util qw(looks_like_number);
use List::Util qw(any);
use English qw( -no_match_vars );
use Data::Dumper;
use Carp;

use Config::FindFile qw(search_conf);
use Log::Log4perl::EasyCatch ( log_config => search_conf( "posemo-logging.properties", "Posemo" ) );

=head3 Constants: STATUS_OK, STATUS_WARNING, STATUS_CRITICAL, STATUS_UNKNOWN

Constants for the result status infos. See status sub.

=cut

use constant {
               STATUS_OK       => 0,
               STATUS_WARNING  => 1,
               STATUS_CRITICAL => 2,
               STATUS_UNKNOWN  => 3,
             };

use base qw(Exporter);
our @EXPORT_OK = qw( STATUS_OK STATUS_WARNING STATUS_CRITICAL STATUS_UNKNOWN );
our %EXPORT_TAGS = ( all => \@EXPORT_OK, status => \@EXPORT_OK );    # at the moment: status and all are the same


#<<< no pertidy formatting

# lazy / build functions


foreach my $attr (qw(class name description code install_sql sql_function sql_function_name result_type order))
   {
   my $builder = "_build_$attr";
   has $attr => ( is => "rw", isa => "Str", lazy => 1, builder => $builder, );
   }

has return_type          => ( is => "ro", isa => "Str",           default   => "boolean", );
has result_unit          => ( is => "ro", isa => "Str",           default   => "", );
has language             => ( is => "ro", isa => "Str",           default   => "sql", );
has volatility           => ( is => "ro", isa => "Str",           default   => "STABLE", );
has has_multiline_result => ( is => "ro", isa => "Bool",          default   => 0, );
has has_writes           => ( is => "ro", isa => "Bool",          default   => 0, );
has arguments            => ( is => "ro", isa => "ArrayRef[Any]", default   => sub { [] }, traits  => ['Array'],
                                                                                           handles =>
                                                                                             {
                                                                                             has_arguments => 'count',
                                                                                             all_arguments => 'elements',
                                                                                             }, );
# options for graphs, display, ...
# Graph type: line, area, stacked_area, ...
# TODO: POD Documentation!
has result_is_counter    => ( is => "ro", isa => "Bool",          predicate => "has_result_is_counter", );
has graph_type           => ( is => "ro", isa => "Str",           predicate => "has_graph_type",        );
has graph_mirrored       => ( is => "ro", isa => "Bool",          predicate => "has_graph_mirrored",    );
has graph_colors         => ( is => "ro", isa => "ArrayRef[Str]", predicate => "has_graph_colors",      );


# The following values can be set via config file etc as parameter
has enabled              => ( is => "ro", isa => "Bool",          default   => 1,);
has warning_level        => ( is => "ro", isa => "Num",           predicate => "has_warning_level", );
has critical_level       => ( is => "ro", isa => "Num",           predicate => "has_critical_level", );
has min_value            => ( is => "ro", isa => "Num",           predicate => "has_min_value", );
has max_value            => ( is => "ro", isa => "Num",           predicate => "has_max_value", );

# Flag for critical/warning check: 
# when true, then check if result is lower else higher then critical/warning_level
has lower_is_worse       => ( is => "ro", isa => "Bool",          predicate => "has_lower_is_worse",);


# Internal states
has app                  => ( is => "ro", isa => "Object",        required  => 1,          handles => [qw(dbh do_sql has_dbh schema user superuser host port host_desc has_host has_port commit rollback)], );
# has result               => ( is => "ro", isa => "ArrayRef[Any]", default   => sub { [] }, ); 

# attributes for attrs with builder method
# the builder looks first here and when nothing found then uses his default
has _code_attr           => ( is => "ro", isa => "Str",           predicate => "has_code_attr", );
has _name_attr           => ( is => "ro", isa => "Str",           predicate => "has_name_attr", );
has _description_attr    => ( is => "ro", isa => "Str",           predicate => "has_description_attr", );
has _result_type_attr    => ( is => "ro", isa => "Str",           predicate => "has_result_type_attr", );
has _install_sql_attr    => ( is => "ro", isa => "Str",           predicate => "has_install_sql_attr", );


# arguments, which may be set from check, or should be set here.
#has result_is_warning    => ( is => "rw", isa => "Bool",          default   => 0, );
#has result_is_critical   => ( is => "rw", isa => "Bool",          default   => 0, );



#>>>


#
# internal default builder methods
# for the default values of the attributes with builder
#

sub _build_class
   {
   my $self = shift;
   return $self unless ref $self;
   return blessed($self);
   }

sub _build_name
   {
   my $self = shift;

   return $self->_name_attr if $self->has_name_attr;

   my $package = __PACKAGE__;
   ( my $name = $self->class ) =~ s{ $package :: }{}ox;

   return _camel_case_to_words($name);
   }

sub _build_description
   {
   my $self = shift;
   return $self->_description_attr if $self->has_description_attr;
   return "The ${ \$self->name } check has no description";
   }

sub _camel_case_to_words
   {
   my $name = shift;
   die "Non-word characters in check name $name\n"                     if $name =~ m{[\W_]}x;
   die "Check package name must start with uppercase letter ($name)\n" if $name =~ m{ ^ [^[:upper:]] }x;

   $name =~ s{ ( [[:lower:][:digit:]]+ ) ( [[:upper:]]+ ) }
             {$1 $2}gx;

   $name =~ s{ ( [[:alpha:]]+ ) ( [[:digit:]]+ ) }
             {$1 $2}gx;

   return $name;
   }

sub _build_sql_function_name
   {
   my $self = shift;
   ( my $function_name = $self->name ) =~ s{\W}{_}gx;
   return lc("${ \$self->schema }.$function_name");
   }

sub _build_code
   {
   my $self = shift;
   return $self->_code_attr if $self->has_code_attr;
   die "The check (${ \$self->class }) must set his Code (or SQL-Function)\n";
   }

sub _build_install_sql
   {
   my $self = shift;
   return $self->_install_sql_attr if $self->has_install_sql_attr;
   return "";
   }

sub _build_sql_function
   {
   my $self = shift;

   my ( @arguments, @arguments_with_default );
   foreach my $par_ref ( $self->all_arguments )
      {
      my $param              = "$par_ref->[0] $par_ref->[1]";
      my $param_with_default = $param;
      if ( defined $par_ref->[2] )
         {
         my $default = $par_ref->[2];

         #         $default = qq{'$default'} unless looks_like_number($default);
         $default = $self->dbh->quote($default) unless looks_like_number($default);
         $param_with_default .= " DEFAULT $default";
         }
      push @arguments,              $param;
      push @arguments_with_default, $param_with_default;
      }

   my $arguments              = join( ", ", @arguments );
   my $arguments_with_default = join( ", ", @arguments_with_default );

   my $setof = "";
   $setof = "SETOF" if $self->has_multiline_result;

   # When return type contains a comma, then we need a new type!
   # because then the return type contains a list of elements
   my $return_type = $self->return_type;
   my $new_type    = "";

   if ( $return_type =~ m{,} )
      {
      #<<<
      $new_type    = "CREATE TYPE ${ \$self->sql_function_name }_type AS ($return_type);"
                   . "ALTER  TYPE ${ \$self->sql_function_name }_type OWNER TO ${ \$self->superuser };";
      $return_type = "${ \$self->sql_function_name }_type";
      #>>>
      }

   return qq{$new_type
  CREATE OR REPLACE FUNCTION ${ \$self->sql_function_name }($arguments_with_default)
    RETURNS $setof $return_type
    AS   
    \$code\$
      ${ \$self->code }
    \$code\$
    LANGUAGE ${ \$self->language }
    ${ \$self->volatility }
    SECURITY DEFINER
    SET search_path = ${ \$self->schema }, pg_temp;
  
  ALTER FUNCTION             ${ \$self->sql_function_name }($arguments) OWNER TO ${ \$self->superuser };
  REVOKE ALL     ON FUNCTION ${ \$self->sql_function_name }($arguments) FROM PUBLIC;
  GRANT  EXECUTE ON FUNCTION ${ \$self->sql_function_name }($arguments) TO ${ \$self->user };
 };

   } ## end sub _build_sql_function

sub _build_result_type
   {
   my $self = shift;

   return $self->_result_type_attr if $self->has_result_type_attr;
   return $self->return_type;                      # result type is by default the same as the return type of the SQL function
   }

sub _build_order
   {
   return shift->name;
   }


=head1 METHODS


=head2 install

This method installs the check on the server.

Executes the SQL from sql_function on the server. 

This method does not commit!

No local error handling, don't disable RaiseError!

Only for installation use, needs an DB connection with 
superuser privileges


=cut

sub install
   {
   my $self = shift;

   if ( $self->install_sql )
      {
      TRACE "${ \$self->sql_function_name }: call extra SQL for installation " . $self->install_sql;
      $self->do_sql( $self->install_sql );
      }

   TRACE "SQL-Function to install: " . $self->sql_function;
   $self->do_sql( $self->sql_function );
   return $self;
   }

=head2 ->run_check()

Executes the check, takes the result, checks for critical/warning and returns the result...

Disabled checks are NOT skipped, this is the job of the caller!

=cut

sub run_check
   {
   my $self = shift;

   INFO "  Run check ${ \$self->name } for host ${ \$self->host_desc }";

   # my $result = $self->enabled ? $self->execute : {};
   my $result = eval {
      my $return = $self->execute;
      $self->commit if $self->has_writes;
      return $return;
   };

   unless ($result)
      {
      $result->{error} = "Error executing SQL function ${ \$self->sql_function_name } from ${ \$self->class }: $EVAL_ERROR\n";
      ERROR $result->{error};
      eval { $self->rollback if $self->has_dbh; return 1; } or ERROR "Error in rollback: $EVAL_ERROR";
      }

   $result->{row_type} //= "none";

   $result->{check_name}        = $self->name;
   $result->{description}       = $self->description;
   $result->{result_unit}       = $self->result_unit;
   $result->{result_type}       = $self->result_type;
   $result->{return_type}       = $self->return_type;
   $result->{sql_function_name} = $self->sql_function_name;

   foreach my $attr (
                      qw(warning_level critical_level
                      min_value max_value
                      lower_is_worse
                      result_is_counter
                      graph_type graph_mirrored graph_colors
                      )
      )
      {
      my $method = "has_$attr";
      next unless $self->$method;
      $result->{$attr} = $self->$attr;
      }

   # skip critical/warning test, when no real result!
   if ( not $result->{error} )
      {
      $self->test_critical_warning($result);
      }

   # according to set status according to critical/warning/error
   $result->{status} = $self->status($result);

   TRACE "Finished check ${ \$self->name } for host ${ \$self->host_desc }";
   TRACE "Result: " . Dumper($result);

   return $result;
   } ## end sub run_check

=head2 execute

Executes the check inside the PostgreSQL server and returns the result.

Throws exception on error!

=cut

sub execute
   {
   my $self = shift;

   my ( @values, @placeholders );

   foreach my $par_ref ( $self->all_arguments )
      {
      my ( $name, $type, $default ) = @$par_ref;
      push @values,       $self->$name // $default;
      push @placeholders, q{?};
      }

   my %result;

   my $placeholders = join( ", ", @placeholders );

   # SELECT with FROM, because function with multiple OUT arguments will result in multiple columns
   TRACE "Prepare: SELECT * FROM ${ \$self->sql_function_name }($placeholders);";
   my $sth = $self->dbh->prepare("SELECT * FROM ${ \$self->sql_function_name }($placeholders);");
   DEBUG "All values for execute: " . join( ", ", map { "'$_'" } @values );
   $sth->execute(@values);

   $result{columns} = $sth->{NAME};

   if ( $self->has_multiline_result )
      {
      $result{result}   = $sth->fetchall_arrayref;
      $result{row_type} = "multiline";
      }
   else
      {
      my @row = $sth->fetchrow_array;

      if ( scalar @row <= 1 )
         {
         $result{result}   = $row[0];
         $result{row_type} = "single";
         }
      else
         {
         $result{result}   = \@row;
         $result{row_type} = "list";
         }
      }

   $sth->finish;

   return \%result;
   } ## end sub execute


=head2 ->test_critical_warning($result)

This method checks, if the result is critical or warning.

It may be overriden in the check to do more detailed checks, see below.

Default check depends on C<result_type> value of the result:

=over 4

=item single

Checks the single value against C<warning_level> / C<critical_level> attribute.

=item list

Checks every value against C<warning_level> / C<critical_level> attribute.

=item multiline

Checks checks every value except the first element of each row against C<warning_level> / C<critical_level> attribute

=back


=head3 Overriding

You may want to override this method. It gets one parameter (beside C<$self>): the complete C<$result>. 
You can use this to write your own critical/warning test in a check module.

You can set the following attributes (hash keys!) in C<$result>:

=over 4

=item *

C<message>: a message, usually used when there is a critical / warning level reached with a description what failed.

=item *

C<critical>: a flag; set it to 1, when the critical level is reached. 

=item *

C<warning>: a flag; set it to 1, when the warning level is reached. 

=back

It is possible to change everything in C<$result>, but usually you should not do this (here).


=cut


sub test_critical_warning
   {
   my $self   = shift;
   my $result = shift;

   if ( $result->{row_type} eq "single" and $self->return_type eq "boolean" )
      {
      return if $result->{result};
      $result->{message}  = "Failed ${ \$self->name } for host ${ \$self->host_desc }";
      $result->{critical} = 1;
      return;
      }


   return unless $self->has_critical_level or $self->has_warning_level;

   my @values;

   if ( $result->{row_type} eq "single" )
      {
      @values = ( $result->{result} );
      }
   elsif ( $result->{row_type} eq "list" )
      {
      @values = @{ $result->{result} };
      }
   elsif ( $result->{row_type} eq "multiline" )
      {
      @values = map { @$_[ 1 .. $#$_ ] } @{ $result->{result} };
      }
   else { $result->{error} = "FATAL: Wrong row_type '${ \$self->result_type }' in critical/warning-check\n"; }

   TRACE "All Values to test for crit/warn: @values";

   my $message = "";

   my ( @crit, @warn );
   if ( $self->lower_is_worse )
      {
      @crit = grep { $_ <= $self->critical_level } @values if $self->has_critical_level;
      @warn = grep { $_ <= $self->warning_level } @values  if $self->has_warning_level;
      }
   else
      {
      @crit = grep { $_ >= $self->critical_level } @values if $self->has_critical_level;
      @warn = grep { $_ >= $self->warning_level } @values  if $self->has_warning_level;
      }

   if (@crit)
      {
      $message = "Critical values: @crit! ";
      $result->{critical} = 1;
      INFO "$message in check ${ \$self->name } for host ${ \$self->host_desc }";
      }

   if (@warn)
      {
      $message .= "; " if $message;
      $message .= "Warning values: @warn! ";
      $result->{warning} = 1;
      INFO "Warning values: @warn in check ${ \$self->name } for host ${ \$self->host_desc }";
      }

   $result->{message} = $message if $message;

   return;
   } ## end sub test_critical_warning


=head2 status

This method returns a C<status> according to the warning/critical flags in the given result.

  0: OK
  1: warning
  2: critical
  3: unknown (e.g. SQL error)

This may be used by some frontend or output modules to interpret the result instead 
of looking into critical/warning result.

This method may be overriden in the check to do something very special and something else then 
looking in warning/critical, but usually this here should be fine and you should 
override C<test_critical_warning> instead (or too).

=cut

sub status
   {
   my $self   = shift;
   my $result = shift // croak "status needs a result hash for checking!";

   return STATUS_CRITICAL if $result->{critical};
   return STATUS_WARNING  if $result->{warning};
   return STATUS_UNKNOWN  if $result->{error};
   return STATUS_OK;
   }


=head2 enabled_on_this_platform

B<Usually you should not use this flag.>

Flag, if the check is globally enabled on the current platform. 

May be overridden in check, to disable some checks on some 
platforms or based on other (non config!) state. When the decision 
is about the configuration or something similar, the attribute 
"enabled" should used/overridden.

When a check module sets C<enabled_on_this_platform> to false, then 
the check will not run, because C<get_all_checks_ordered> removes it.

This should only be dependent on the platform the application is 
running (local), not the PostgreSQL server (remote). 


=cut

sub enabled_on_this_platform
   {
   return 1;
   }



__PACKAGE__->meta->make_immutable;

1;

