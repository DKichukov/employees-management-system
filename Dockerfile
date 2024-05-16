FROM xldevops/jdk17-alpine
EXPOSE 8080
ARG JAR_FILE=/target/*.jar
COPY ${JAR_FILE} application.jar
ENTRYPOINT [ "sh", "-c", "java -jar application.jar" ]

#ENTRYPOINT ["java","-jar","/app.jar"]

#CMD ["java","-jar","app.jar"]