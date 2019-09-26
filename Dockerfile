# dockerfile to build image for JBoss EAP 7.1

#start from eap71-openshift
FROM jboss/wildfly:17.0.1.Final

# Copy war to deployments folder
COPY target/spring-resteasy.war "$JBOSS_HOME/standalone/deployments/"

# User root to modify war owners
USER root

# Modify owners war
RUN chown jboss:jboss "$JBOSS_HOME/standalone/deployments/spring-resteasy.war"

# Important, use jboss user to run image
USER jboss
