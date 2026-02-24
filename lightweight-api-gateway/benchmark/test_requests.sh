#!/bin/bash
# Test script to verify all implementations work consistently

GATEWAY_PORT=8080
BASE_URL="http://localhost:$GATEWAY_PORT"

echo "Testing API Gateway implementations..."

# Test health check
echo "1. Health Check:"
curl -s "$BASE_URL/health" | jq .

# Test public endpoint
echo "2. Public Endpoint:"
curl -s "$BASE_URL/public/info" | jq .

# Test protected endpoint without JWT (should fail)
echo "3. Protected Endpoint (no JWT):"
curl -s "$BASE_URL/api/protected" | jq .

# Test protected endpoint with JWT
echo "4. Protected Endpoint (with JWT):"
curl -s -H "Authorization: Bearer valid-test-token" "$BASE_URL/api/protected" | jq .

# Test API endpoint with JWT
echo "5. API Endpoint (with JWT):"
curl -s -H "Authorization: Bearer valid-test-token" "$BASE_URL/api/test" | jq .

# Test rate limiting (multiple quick requests)
echo "6. Rate Limiting Test:"
for i in {1..5}; do
    echo "Request $i:"
    curl -s "$BASE_URL/api/test" | jq -r '.message // .error'
done

echo "Testing complete!"
