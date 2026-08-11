FROM public.ecr.aws/lambda/nodejs:22

# Copy package files
COPY package*.json ${LAMBDA_TASK_ROOT}/

# Install production dependencies only
RUN npm ci --omit=dev

# Copy compiled JavaScript
COPY dist/ ${LAMBDA_TASK_ROOT}/

# Set the handler
CMD ["handler.handler"]
