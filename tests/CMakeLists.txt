cmake_minimum_required(VERSION 3.18.1)
project(opuslib-tests)

set(CMAKE_C_STANDARD 11)

# Build opus from source
add_subdirectory(
  ${CMAKE_CURRENT_SOURCE_DIR}/../thirdparty/opus-1.6
  ${CMAKE_CURRENT_BINARY_DIR}/opus-build
)

# Encode/decode round-trip test
add_executable(test_opus_encode_decode test_opus_encode_decode.c)
target_link_libraries(test_opus_encode_decode opus m)
target_include_directories(test_opus_encode_decode PRIVATE
  ${CMAKE_CURRENT_SOURCE_DIR}/../thirdparty/opus-1.6/include
)
