// Copyright 2012 Cloudera Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#ifndef IMPALA_UTIL_JSON_UTIL_H
#define IMPALA_UTIL_JSON_UTIL_H

#include <rapidjson/rapidjson.h>
#include <rapidjson/document.h>

#include "util/template-util.h"
#include "util/pretty-printer.h"

namespace impala {

// ToJsonValue() converts 'value' into a rapidjson::Value in 'out_val'. The type of
// 'out_val' depends on the value of 'type'. If type != TUnit::NONE and 'value' is
// numeric, 'value' will be set to a string which is the pretty-printed representation of
// 'value' (e.g. conversion to MB etc). Otherwise the value is directly copied into
// 'out_val'.
template <typename T>
ENABLE_IF_NOT_ARITHMETIC(T, void)
ToJsonValue(const T& value, const TUnit::type unit, rapidjson::Document* document,
    rapidjson::Value* out_val) {
  *out_val = value;
}

// Specialisation for std::string which requires explicit use of 'document's allocator to
// copy into out_val.
template <>
void ToJsonValue<std::string>(const std::string& value, const TUnit::type unit,
    rapidjson::Document* document, rapidjson::Value* out_val);

// Does pretty-printing if 'value' is numeric, and type is not NONE, otherwise constructs
// a json object containing 'value' as a literal.
template <typename T>
ENABLE_IF_ARITHMETIC(T, void)
ToJsonValue(const T& value, const TUnit::type unit, rapidjson::Document* document,
    rapidjson::Value* out_val) {
  if (unit != TUnit::NONE) {
    const std::string& s = PrettyPrinter::Print(value, unit);
    ToJsonValue(s, unit, document, out_val);
  } else {
    *out_val = value;
  }
}

}

#endif
