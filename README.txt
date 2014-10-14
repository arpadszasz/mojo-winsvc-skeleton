Setting up the development environment
======================================

1. download and install ActivePerl (Windows x86) minimum version 5.16 from http://www.activestate.com/activeperl/downloads

2. download and install PerlDevKit (Windows x86) minimum version 9.3 from http://www.activestate.com/perl-dev-kit/downloads

3. install PerlDevKit license

4. download and install InnoSetup (Unicode) minimum version 5.1 from http://www.innosetup.com/isdl.php

5. clone GIT source code repository:

    a) using GIT command line client
        - create an account on https://bitbucket.org
        - install GIT command line client from http://www.git-scm.com/download/win
        - open CMD.EXE (Start -> Run -> cmd)
        - clone using the command: git clone https://...

    b) using SourceTree GIT desktop client
        - create an account on https://bitbucket.org
        - download SourceTree from http://www.sourcetreeapp.com/download
        - start SourceTree (Start -> All Programs -> Atlassian -> SourceTree -> SourceTree)
        - go to menu: File -> Clone / New
        - fill in Source Path / URL to https://...
        - fill in Destination Path
        - authenticate using your BitBucket.org account's username and password
        - click Clone

6. install Perl module dependencies by running: setup-perl-dependencies.bat

7. edit "release.ini" file and set:
    - product name, company (required)
    - server address, port (optional, defaults to "localhost" and "3000")
    - ODBC alias, username and password (required)

8. start the development environment by running: start-dev-server.bat


Create program releases
=======================

1. check if the "perlsvc", "perlapp" and "innosetup" program paths need changing in the "release.ini" file

2. if you want to build the client browser application you need to set in "release.ini":
    [client]
    build = 1

3. run the release script: build-release.bat

Notes about the "build-release.bat" script:
    - exe files are generated in the dist\ folder
    - the installer is generated in the installer\ folder
    - it automatically finds all the Perl modules in web\lib and Mojolicious templates in web\templates and adds them to the PerlSvc project file
    - it generates the PerlSvc project file in "pdk\*.perlsvc"
    - it generates the InnoSetup project file in "installer\innosetup.iss"
    - it is generated from "build-release.pl" by running: pl2bat build-release.pl

Notes about the "build-client-exe.bat" script:
    - exe file is generated in the dist\ folder
    - it automatically finds all the required wxPerl DLL files and adds them to the PerlApp project file
    - it generates the PerlApp project file in "pdk\*.perlapp"
    - it is generated from "build-exe-client.pl" by running (in the "client\" folder): pl2bat build-client-exe.pl


Common errors
=============

When executed from a network drive (UNC path) the "build-release.bat" script gives the error "UNC paths are not supported.  Defaulting to Windows directory.". The solution is to copy the source code folder to a local path (like the Desktop) and run it from there.

When executed from a network drive (UNC path) the installer gives the error message "ShellExecuteEx failed; code 3. The system cannot find the path specified". The solution is to copy the installer to a local path (like the Desktop) and run it from there.
