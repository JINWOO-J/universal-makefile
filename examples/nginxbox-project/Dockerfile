   # Dockerfile
   FROM nginx:alpine

   # 환경변수로 버전 입력받기
   ARG VERSION
   ENV VERSION=${VERSION}

   # index.html을 컨테이너에 복사
   COPY app/index.html /usr/share/nginx/html/index.html
      
   RUN sed -i "s/{{VERSION}}/${VERSION}/g" /usr/share/nginx/html/index.html


   # nginx 실행
   CMD ["nginx", "-g", "daemon off;"]