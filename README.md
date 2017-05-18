# Posemo – PostgreSQL Secure Monitoring

Posemo is a PostgreSQL monitoring framework, that can monitor everything in Postgres with an unprivileged user. Posemo conforms to the rules of the German Federal Office for Information Security (Bundesamt für Sicherheit in der Informationstechnik, BSI).

Posemo itself has no display capabilities, but can output the results for every monitoring environment (e.g. check_mk, Nagios, Zabbix, Icinga, …).

…

## This is a Pre-Release, for Developers only!

More documentation will come. Posemo is in development an not yet usable!
**See dev branch for the code!**

Some parts of the documentation are missing.

THERE WILL BE DRAGONS!


## Concepts

Posemo is a modular framework for creating Monitoring Checks for PostgreSQL. It is simple to add a new check. Usually just have to write the SQL for the check and add some configuration.

Posemo is a modern Perl application using Moose; at installation it generates PostgerSQL functions for every check. These functions are called by an unprivileged user who can only call there functions, nothing else. But since they are `SECURITY DEFINER` functions, they run with more privileges (usually as superuser). You need a superuser for installation, but checks can run (from remote or local) by an unprivileged user. Therefore, **the monitoring server has no access to your databases, no access to PostgreSQL internals – it can only call some predefined functions.**




##  Author

Posemo is written by [Alvar C.H. Freude](http://alvar.a-blast.org/), 2016–2017.

alvar@a-blast.org


## License

Posemo is released under the [PostgreSQL License](https://opensource.org/licenses/postgresql), a liberal Open Source license, similar to the BSD or MIT licenses.


Copyright (c) 2016, 2017, Alvar C.H. Freude and contributors

Permission to use, copy, modify, and distribute this software and its documentation for any purpose, without fee, and without a written agreement is hereby granted, provided that the above copyright notice and this paragraph and the following two paragraphs appear in all copies.

IN NO EVENT SHALL THE AUTHOR BE LIABLE TO ANY PARTY FOR DIRECT, INDIRECT, SPECIAL, INCIDENTAL, OR CONSEQUENTIAL DAMAGES, INCLUDING LOST PROFITS, ARISING OUT OF THE USE OF THIS SOFTWARE AND ITS DOCUMENTATION, EVEN IF THE AUTHOR HAS BEEN ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

THE AUTHOR SPECIFICALLY DISCLAIMS ANY WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE. THE SOFTWARE PROVIDED HEREUNDER IS ON AN "AS IS" BASIS, AND THE AUTHOR HAS NO OBLIGATIONS TO PROVIDE MAINTENANCE, SUPPORT, UPDATES, ENHANCEMENTS, OR MODIFICATIONS.
