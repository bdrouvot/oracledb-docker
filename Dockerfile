# Pull base image
# ---------------
FROM oraclelinux:latest

# Maintainer
# ----------
MAINTAINER Bertrand Drouvot <bdtoracleblog@gmail.com>

# Environment variables required for this build 
# Change:
#     ORACLE_PWD: SYS, SYSTEM, PDBADMIN password
#     MOSU: Your Oracle Support User
#     MOSU: The Associated Oracle Support password
# -------------------------------------------------------------
ENV ORACLE_BASE=/opt/oracle \
    ORACLE_HOME=/opt/oracle/product/12.1.0.2/dbhome_1 \
    ORACLE_SID=ORCLCDB \
    ORACLE_PDB=ORCLPDB1 \
    INSTALL_FILE_1="p21419221_121020_Linux-x86-64_1of10.zip" \
    INSTALL_FILE_2="p21419221_121020_Linux-x86-64_2of10.zip" \
    INSTALL_RSP="db_inst.rsp" \
    CONFIG_RSP="dbca.rsp" \
    PERL_INSTALL_FILE="installPerl.sh" \
    RUN_FILE="runOracle.sh" \ 
    ORACLE_PWD="<put_the_password_you_want>" \
    MOSU="<your_oracle_support_username>" \
    MOSP="<your_oracle_support_password>"

# Use second ENV so that variable get substituted
ENV INSTALL_DIR=$ORACLE_BASE/install \
    PATH=$ORACLE_HOME/bin:$ORACLE_HOME/OPatch/:/usr/sbin:$PATH \
    LD_LIBRARY_PATH=$ORACLE_HOME/lib:/usr/lib \
    CLASSPATH=$ORACLE_HOME/jlib:$ORACLE_HOME/rdbms/jlib

# Copy binaries
# -------------
COPY .getMOSPatch.sh.cfg getMOSPatch.sh $INSTALL_RSP $CONFIG_RSP $PERL_INSTALL_FILE $INSTALL_DIR/
COPY $RUN_FILE $ORACLE_BASE/

# Setup filesystem and oracle user
# Adjust file permissions, go to /opt/oracle as user 'oracle' to proceed with Oracle installation
# ------------------------------------------------------------
RUN mkdir -p $ORACLE_BASE && \
    groupadd -g 500 dba && \
    groupadd -g 501 oinstall && \
    useradd -d /home/oracle -g dba -G oinstall,dba -m -s /bin/bash oracle && \
    echo oracle:oracle | chpasswd && \
    yum -y install oracle-rdbms-server-12cR1-preinstall unzip wget tar perl && \
    yum clean all && \
    chown -R oracle:dba $ORACLE_BASE

WORKDIR $INSTALL_DIR

# Replace place holders
# ---------------------
RUN sed -i -e "s|###ORACLE_EDITION###|EE|g" $INSTALL_DIR/$INSTALL_RSP &&        \
    sed -i -e "s|###ORACLE_BASE###|$ORACLE_BASE|g" $INSTALL_DIR/$INSTALL_RSP && \
    sed -i -e "s|###ORACLE_HOME###|$ORACLE_HOME|g" $INSTALL_DIR/$INSTALL_RSP && \
    sed -i -e "s|###ORACLE_SID###|$ORACLE_SID|g" $INSTALL_DIR/$CONFIG_RSP &&    \
    sed -i -e "s|###ORACLE_PDB###|$ORACLE_PDB|g" $INSTALL_DIR/$CONFIG_RSP &&    \
    sed -i -e "s|###ORACLE_PWD###|$ORACLE_PWD|g" $INSTALL_DIR/$CONFIG_RSP

# Download the Distribution

RUN export mosUser=$MOSU && \
    export mosPass=$MOSP && \
    export DownList=2 && \ 
    sh ./getMOSPatch.sh patch=21419221 && \
    export DownList=3 && \
    sh ./getMOSPatch.sh patch=21419221

# Start installation
# -------------------
USER oracle

RUN unzip $INSTALL_FILE_1 && \
    rm $INSTALL_FILE_1 &&    \
    unzip $INSTALL_FILE_2 && \
    rm $INSTALL_FILE_2 &&    \
    $INSTALL_DIR/database/runInstaller -silent -force -waitforcompletion -responsefile $INSTALL_DIR/$INSTALL_RSP -ignoresysprereqs -ignoreprereq && \
    rm -rf $INSTALL_DIR/database

# Check whether Perl is working
RUN chmod u+x $INSTALL_DIR/installPerl.sh && \
    $ORACLE_HOME/perl/bin/perl -v || \
    $INSTALL_DIR/installPerl.sh

USER root
RUN $ORACLE_BASE/oraInventory/orainstRoot.sh && \
    $ORACLE_HOME/root.sh

USER oracle
WORKDIR /home/oracle

RUN mkdir -p $ORACLE_HOME/network/admin && \
    echo "NAME.DIRECTORY_PATH= {TNSNAMES, EZCONNECT, HOSTNAME}" > $ORACLE_HOME/network/admin/sqlnet.ora

# Listener.ora
RUN echo "LISTENER = \
  (DESCRIPTION_LIST = \
    (DESCRIPTION = \
      (ADDRESS = (PROTOCOL = IPC)(KEY = EXTPROC1)) \
      (ADDRESS = (PROTOCOL = TCP)(HOST = 0.0.0.0)(PORT = 1521)) \
    ) \
  ) \
\
" > $ORACLE_HOME/network/admin/listener.ora

RUN echo "DEDICATED_THROUGH_BROKER_LISTENER=ON"  >> $ORACLE_HOME/network/admin/listener.ora && \
    echo "DEFAULT_SERVICE_LISTENER = ($ORACLE_SID)" >> $ORACLE_HOME/network/admin/listener.ora && \
    echo "DIAG_ADR_ENABLED = off"  >> $ORACLE_HOME/network/admin/listener.ora;

# Start LISTENER and run DBCA
RUN bash -lc "lsnrctl start" && \
    dbca -silent -responseFile $INSTALL_DIR/$CONFIG_RSP || \
    cat /opt/oracle/cfgtoollogs/dbca/$ORACLE_SID/$ORACLE_SID.log

RUN echo "$ORACLE_SID=localhost:1521/$ORACLE_SID" >> $ORACLE_HOME/network/admin/tnsnames.ora && \
    echo "$ORACLE_PDB= \
  (DESCRIPTION = \
    (ADDRESS = (PROTOCOL = TCP)(HOST = 0.0.0.0)(PORT = 1521)) \
    (CONNECT_DATA = \
      (SERVER = DEDICATED) \
      (SERVICE_NAME = $ORACLE_PDB) \
    ) \
  )" >> /$ORACLE_HOME/network/admin/tnsnames.ora

RUN echo "startup;" | sqlplus / as sysdba && \
    echo "ALTER PLUGGABLE DATABASE $ORACLE_PDB OPEN;" | sqlplus / as sysdba && \
    echo "ALTER PLUGGABLE DATABASE $ORACLE_PDB SAVE STATE;" | sqlplus / as sysdba

RUN rm -rf $INSTALL_DIR
EXPOSE 1521 5500

# Define default command to start Oracle Database.
CMD $ORACLE_BASE/$RUN_FILE
