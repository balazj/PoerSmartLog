# PoerSmartLog
Log heating data for later analisys.

# Installation
1. Please make sure that you have following requirements installed:
- DBD::mysql
- JSON::XS
- XML::Parser

2. Update Kernel/Config/Settings.xml:
- Email - email that is used in your PoerSmart app.
- Password - password that is used in your PoerSmart app.
- URL - this part might be difficult since it depends on your User ID (which is not something that is visible).
        It has format http://open.poersmart.com:8012/newUsers/1234/1234/nodes, but you might want to use WireShark or other application in order to figure this out.
- Realm - realm name, default value 'Protected' should work out.
- Location - realm location, default value 'open.poersmart.com:8012' should work out.

3. Update MySQL connection settings in Kernel/Config/Database.xml:
- DSN - it has format 'DBI:mysql:database=PoerSmartLog;host=localhost;'. You might want to change PoerSmartLog
        (DB name) if you want to split your logs on yearly basis for example, however default should work out.
        Also, host parameter ('localhost') should be updated if your MySQL is not installed on the same system.
- USER - MySQL user
- PW - MySQL password

4. Setup Database:
- Make sure that database with same name doesn't exist(configured in DSN).
- Run bin/Install.pl - create DB and necesarry tables.

5. Run bin/PoerSmartLog.pl manually, or set up a scheduler task to do it periodically (each minute or so).
