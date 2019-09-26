# dockerfile to build image for JBoss EAP 7.1

#start from eap71-openshift
FROM registry.access.redhat.com/jboss-eap-7/eap71-openshift

# Copy war to deployments folder
COPY app.war $JBOSS_HOME/standalone/deployments/

# User root to modify war owners
USER root

# Modify owners war
RUN chown jboss:jboss "$JBOSS_HOME/standalone/deployments/app.war"

# Important, use jboss user to run image
USER jboss
