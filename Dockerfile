# Lightweight base image
FROM google/cloud-sdk:slim

# Set working directory
WORKDIR /app

# Copy scripts and config
COPY test.sh .

# Ensure script is executable
RUN chmod +x test.sh

# Cloud Run Jobs execute CMD once and exit
CMD ["./test.sh"]
