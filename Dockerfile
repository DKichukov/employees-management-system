FROM openjdk:17
EXPOSE 8080
ARG JAR_FILE=target/ems-app.jar
COPY ${JAR_FILE} application.jar
ENTRYPOINT ["java", "-jar" ,"/application.jar" ]