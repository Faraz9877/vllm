// clang-format will break include orders
// clang-format off
#include <cudaTypedefs.h>

#if defined CUDA_VERSION && CUDA_VERSION >= 12000

#include <torch/all.h>

#include <ATen/cuda/CUDAContext.h>

#include <iostream>
#include <sstream>
#include <vector>

#include "cutlass/cutlass.h"

#include "cute/tensor.hpp"
#include "cute/atom/mma_atom.hpp"
#include "cutlass/numeric_types.h"

#include "cutlass/gemm/device/gemm_universal_adapter.h"
#include "cutlass/gemm/kernel/gemm_universal.hpp"
#include "cutlass/epilogue/collective/collective_builder.hpp"
#include "cutlass/gemm/collective/collective_builder.hpp"

#include "util/broadcast_load_epilogue_c3x.hpp"
#include "util/common.hpp"
// clang-format on

#include "sparse_scaled_mm_c3x.cuh"
#include "sparse_scaled_mm_c3x_configs.cuh"

template <typename InType, typename OutType,
          template <typename, typename, typename> typename Epilogue,
          typename... EpilogueArgs>
void cutlass_gemm_sm90_fp8_dispatch(torch::Tensor& out, torch::Tensor const& a,
                                    torch::Tensor const& e,
                                    torch::Tensor const& b,
                                    EpilogueArgs&&... args) {
  static_assert(std::is_same<InType, cutlass::float_e4m3_t>());
  TORCH_CHECK(a.dtype() == torch::kFloat8_e4m3fn);
  TORCH_CHECK(e.dtype() == torch::kUInt8);
  TORCH_CHECK(b.dtype() == torch::kFloat8_e4m3fn);

  using Cutlass3xGemmDefault =
      typename sm90_fp8_config_default<InType, OutType,
                                       Epilogue>::Cutlass3xGemm;
  using Cutlass3xGemmM64 =
      typename sm90_fp8_config_M64<InType, OutType, Epilogue>::Cutlass3xGemm;
  using Cutlass3xGemmM128 =
      typename sm90_fp8_config_M128<InType, OutType, Epilogue>::Cutlass3xGemm;
  using Cutlass3xGemmM256 =
      typename sm90_fp8_config_M256<InType, OutType, Epilogue>::Cutlass3xGemm;
  using Cutlass3xGemmM512 =
      typename sm90_fp8_config_M512<InType, OutType, Epilogue>::Cutlass3xGemm;
    
  using Cutlass3xGemm1 =
      typename sm90_fp8_config_1<InType, OutType, Epilogue>::Cutlass3xGemm;
  using Cutlass3xGemm2 =
      typename sm90_fp8_config_2<InType, OutType, Epilogue>::Cutlass3xGemm;
  using Cutlass3xGemm3 =
      typename sm90_fp8_config_3<InType, OutType, Epilogue>::Cutlass3xGemm;
  using Cutlass3xGemm4 =
      typename sm90_fp8_config_4<InType, OutType, Epilogue>::Cutlass3xGemm;
  using Cutlass3xGemm5 =
      typename sm90_fp8_config_5<InType, OutType, Epilogue>::Cutlass3xGemm;
  using Cutlass3xGemm6 =
      typename sm90_fp8_config_6<InType, OutType, Epilogue>::Cutlass3xGemm;
  using Cutlass3xGemm7 =
      typename sm90_fp8_config_7<InType, OutType, Epilogue>::Cutlass3xGemm;
  using Cutlass3xGemm8 =
      typename sm90_fp8_config_8<InType, OutType, Epilogue>::Cutlass3xGemm;

  uint32_t const n = b.size(1); // Batch size
  uint32_t const m = a.size(0);
  uint32_t const np2 =
      std::max(static_cast<uint32_t>(64), next_pow_2(n));  // next power of 2

  if (np2 <= 64) {
    if (m == 28672) {
      return cutlass_sparse_gemm_caller<Cutlass3xGemm2>(
        out, a, e, b, std::forward<EpilogueArgs>(args)...);
    }
    else if (m == 4096 || m == 6144) {
      return cutlass_sparse_gemm_caller<Cutlass3xGemm1>(
        out, a, e, b, std::forward<EpilogueArgs>(args)...);
    }
  } else if (np2 <= 128) {
    if (m == 4096) {
      return cutlass_sparse_gemm_caller<Cutlass3xGemm3>(
        out, a, e, b, std::forward<EpilogueArgs>(args)...);
    }
    else if (m == 28672) {
      return cutlass_sparse_gemm_caller<Cutlass3xGemm5>(
        out, a, e, b, std::forward<EpilogueArgs>(args)...);
    }
    else if (m == 6144) {
      return cutlass_sparse_gemm_caller<Cutlass3xGemm4>(
        out, a, e, b, std::forward<EpilogueArgs>(args)...);
    }
  } else if (np2 <= 256) {
    if (m == 4096) {
      return cutlass_sparse_gemm_caller<Cutlass3xGemm6>(
        out, a, e, b, std::forward<EpilogueArgs>(args)...);
    }
    else if (m == 28672) {
      return cutlass_sparse_gemm_caller<Cutlass3xGemm8>(
        out, a, e, b, std::forward<EpilogueArgs>(args)...);
    }
    else if (m == 6144) {
      return cutlass_sparse_gemm_caller<Cutlass3xGemm7>(
        out, a, e, b, std::forward<EpilogueArgs>(args)...);
    }
  } else {
    if (m == 6144 || m == 28672) {
      return cutlass_sparse_gemm_caller<Cutlass3xGemm8>(
        out, a, e, b, std::forward<EpilogueArgs>(args)...);
    }
    else if (m == 4096) {
      return cutlass_sparse_gemm_caller<Cutlass3xGemm7>(
        out, a, e, b, std::forward<EpilogueArgs>(args)...);
    }
  }

  // Otherwise the default heuristic
  if (np2 <= 64) {
    // n in [1, 64]
    return cutlass_sparse_gemm_caller<Cutlass3xGemmM64>(
        out, a, e, b, std::forward<EpilogueArgs>(args)...);
  } else if (np2 <= 128) {
    // n in (64, 128]
    return cutlass_sparse_gemm_caller<Cutlass3xGemmM128>(
        out, a, e, b, std::forward<EpilogueArgs>(args)...);
  } else if (np2 <= 256) {
    // n in (128, 256]
    return cutlass_sparse_gemm_caller<Cutlass3xGemmM256>(
        out, a, e, b, std::forward<EpilogueArgs>(args)...);
  } else {
    // n in (256, inf)
    return cutlass_sparse_gemm_caller<Cutlass3xGemmM512>(
        out, a, e, b, std::forward<EpilogueArgs>(args)...);
  }
}

template <typename InType, typename OutType,
          template <typename, typename, typename> typename Epilogue,
          typename... EpilogueArgs>
void cutlass_gemm_sm90_fp16_dispatch(torch::Tensor& out, torch::Tensor const& a,
                                    torch::Tensor const& e,
                                    torch::Tensor const& b,
                                    EpilogueArgs&&... args) {
  static_assert(std::is_same<InType, cutlass::half_t>());
  TORCH_CHECK(a.dtype() == torch::kFloat16);
  TORCH_CHECK(e.dtype() == torch::kUInt8);
  TORCH_CHECK(b.dtype() == torch::kFloat16);

  uint32_t const m = out.size(1);
  uint32_t const n = out.size(0);
  uint32_t const k = b.size(0);

  if (m == 1) {
        if (n == 4096 && k == 4096)
            return cutlass_sparse_gemm_caller<typename sm90_fp16_config_0
                <InType, OutType, Epilogue>::Cutlass3xGemm >(
                out, a, e, b, std::forward<EpilogueArgs>(args)...);
        if (n == 4096 && k == 14336)
            return cutlass_sparse_gemm_caller<typename sm90_fp16_config_1
                <InType, OutType, Epilogue>::Cutlass3xGemm >(
                out, a, e, b, std::forward<EpilogueArgs>(args)...);
        if (n == 6144 && k == 4096)
            return cutlass_sparse_gemm_caller<typename sm90_fp16_config_2
                <InType, OutType, Epilogue>::Cutlass3xGemm >(
                out, a, e, b, std::forward<EpilogueArgs>(args)...);
        if (n == 28672 && k == 4096)
            return cutlass_sparse_gemm_caller<typename sm90_fp16_config_3
                <InType, OutType, Epilogue>::Cutlass3xGemm >(
                out, a, e, b, std::forward<EpilogueArgs>(args)...);
    } else if (m <= 16) {
        if (n == 4096 && k == 4096)
            return cutlass_sparse_gemm_caller<typename sm90_fp16_config_4
                <InType, OutType, Epilogue>::Cutlass3xGemm >(
                out, a, e, b, std::forward<EpilogueArgs>(args)...);
        if (n == 4096 && k == 14336)
            return cutlass_sparse_gemm_caller<typename sm90_fp16_config_5
                <InType, OutType, Epilogue>::Cutlass3xGemm >(
                out, a, e, b, std::forward<EpilogueArgs>(args)...);
        if (n == 6144 && k == 4096)
            return cutlass_sparse_gemm_caller<typename sm90_fp16_config_6
                <InType, OutType, Epilogue>::Cutlass3xGemm >(
                out, a, e, b, std::forward<EpilogueArgs>(args)...);
        if (n == 28672 && k == 4096)
            return cutlass_sparse_gemm_caller<typename sm90_fp16_config_7
                <InType, OutType, Epilogue>::Cutlass3xGemm >(
                out, a, e, b, std::forward<EpilogueArgs>(args)...);
    } else if (m <= 32) {
        if (n == 4096 && k == 4096)
            return cutlass_sparse_gemm_caller<typename sm90_fp16_config_8
                <InType, OutType, Epilogue>::Cutlass3xGemm >(
                out, a, e, b, std::forward<EpilogueArgs>(args)...);
        if (n == 4096 && k == 14336)
            return cutlass_sparse_gemm_caller<typename sm90_fp16_config_9
                <InType, OutType, Epilogue>::Cutlass3xGemm >(
                out, a, e, b, std::forward<EpilogueArgs>(args)...);
        if (n == 6144 && k == 4096)
            return cutlass_sparse_gemm_caller<typename sm90_fp16_config_10
                <InType, OutType, Epilogue>::Cutlass3xGemm >(
                out, a, e, b, std::forward<EpilogueArgs>(args)...);
        if (n == 28672 && k == 4096)
            return cutlass_sparse_gemm_caller<typename sm90_fp16_config_11
                <InType, OutType, Epilogue>::Cutlass3xGemm >(
                out, a, e, b, std::forward<EpilogueArgs>(args)...);
    } else if (m <= 64) {
        if (n == 4096 && k == 4096)
            return cutlass_sparse_gemm_caller<typename sm90_fp16_config_12
                <InType, OutType, Epilogue>::Cutlass3xGemm >(
                out, a, e, b, std::forward<EpilogueArgs>(args)...);
        if (n == 4096 && k == 14336)
            return cutlass_sparse_gemm_caller<typename sm90_fp16_config_13
                <InType, OutType, Epilogue>::Cutlass3xGemm >(
                out, a, e, b, std::forward<EpilogueArgs>(args)...);
        if (n == 6144 && k == 4096)
            return cutlass_sparse_gemm_caller<typename sm90_fp16_config_14
                <InType, OutType, Epilogue>::Cutlass3xGemm >(
                out, a, e, b, std::forward<EpilogueArgs>(args)...);
        if (n == 28672 && k == 4096)
            return cutlass_sparse_gemm_caller<typename sm90_fp16_config_15
                <InType, OutType, Epilogue>::Cutlass3xGemm >(
                out, a, e, b, std::forward<EpilogueArgs>(args)...);
    } else if (m <= 128) {
        if (n == 4096 && k == 4096)
            return cutlass_sparse_gemm_caller<typename sm90_fp16_config_16
                <InType, OutType, Epilogue>::Cutlass3xGemm >(
                out, a, e, b, std::forward<EpilogueArgs>(args)...);
        if (n == 4096 && k == 14336)
            return cutlass_sparse_gemm_caller<typename sm90_fp16_config_17
                <InType, OutType, Epilogue>::Cutlass3xGemm >(
                out, a, e, b, std::forward<EpilogueArgs>(args)...);
        if (n == 6144 && k == 4096)
            return cutlass_sparse_gemm_caller<typename sm90_fp16_config_18
                <InType, OutType, Epilogue>::Cutlass3xGemm >(
                out, a, e, b, std::forward<EpilogueArgs>(args)...);
        if (n == 28672 && k == 4096)
            return cutlass_sparse_gemm_caller<typename sm90_fp16_config_19
                <InType, OutType, Epilogue>::Cutlass3xGemm >(
                out, a, e, b, std::forward<EpilogueArgs>(args)...);
    } else if (m <= 256) {
        if (n == 4096 && k == 4096)
            return cutlass_sparse_gemm_caller<typename sm90_fp16_config_20
                <InType, OutType, Epilogue>::Cutlass3xGemm >(
                out, a, e, b, std::forward<EpilogueArgs>(args)...);
        if (n == 4096 && k == 14336)
            return cutlass_sparse_gemm_caller<typename sm90_fp16_config_21
                <InType, OutType, Epilogue>::Cutlass3xGemm >(
                out, a, e, b, std::forward<EpilogueArgs>(args)...);
        if (n == 6144 && k == 4096)
            return cutlass_sparse_gemm_caller<typename sm90_fp16_config_22
                <InType, OutType, Epilogue>::Cutlass3xGemm >(
                out, a, e, b, std::forward<EpilogueArgs>(args)...);
        if (n == 28672 && k == 4096)
            return cutlass_sparse_gemm_caller<typename sm90_fp16_config_23
                <InType, OutType, Epilogue>::Cutlass3xGemm >(
                out, a, e, b, std::forward<EpilogueArgs>(args)...);
    } else { // m512 kernels
        if (n == 4096 && k == 4096)
            return cutlass_sparse_gemm_caller<typename sm90_fp16_config_24
                <InType, OutType, Epilogue>::Cutlass3xGemm >(
                out, a, e, b, std::forward<EpilogueArgs>(args)...);
        if (n == 4096 && k == 14336)
            return cutlass_sparse_gemm_caller<typename sm90_fp16_config_25
                <InType, OutType, Epilogue>::Cutlass3xGemm >(
                out, a, e, b, std::forward<EpilogueArgs>(args)...);
        if (n == 6144 && k == 4096)
            return cutlass_sparse_gemm_caller<typename sm90_fp16_config_26
                <InType, OutType, Epilogue>::Cutlass3xGemm >(
                out, a, e, b, std::forward<EpilogueArgs>(args)...);
        if (n == 28672 && k == 4096)
            return cutlass_sparse_gemm_caller<typename sm90_fp16_config_27
                <InType, OutType, Epilogue>::Cutlass3xGemm >(
                out, a, e, b, std::forward<EpilogueArgs>(args)...);
    }

  using Cutlass3xGemmDefault =
      typename sm90_fp16_config_default<InType, OutType,
                                       Epilogue>::Cutlass3xGemm;

    // m in (128, inf)
    return cutlass_sparse_gemm_caller<Cutlass3xGemmDefault>(
        out, a, e, b, std::forward<EpilogueArgs>(args)...);
}

template <typename InType, typename OutType,
          template <typename, typename, typename> typename Epilogue,
          typename... EpilogueArgs>
void cutlass_gemm_sm90_bf16_dispatch(torch::Tensor& out, torch::Tensor const& a,
                                    torch::Tensor const& e,
                                    torch::Tensor const& b,
                                    EpilogueArgs&&... args) {
  static_assert(std::is_same<InType, cutlass::bfloat16_t>());
  TORCH_CHECK(a.dtype() == torch::kBFloat16);
  TORCH_CHECK(e.dtype() == torch::kUInt8);
  TORCH_CHECK(b.dtype() == torch::kBFloat16);

  uint32_t const m = out.size(1);
  uint32_t const n = out.size(0);
  uint32_t const k = b.size(0);

  if (m == 1) {
        if (n == 4096 && k == 4096)
            return cutlass_sparse_gemm_caller<typename sm90_bf16_config_0
                <InType, OutType, Epilogue>::Cutlass3xGemm >(
                out, a, e, b, std::forward<EpilogueArgs>(args)...);
        if (n == 4096 && k == 14336)
            return cutlass_sparse_gemm_caller<typename sm90_bf16_config_1
                <InType, OutType, Epilogue>::Cutlass3xGemm >(
                out, a, e, b, std::forward<EpilogueArgs>(args)...);
        if (n == 6144 && k == 4096)
            return cutlass_sparse_gemm_caller<typename sm90_bf16_config_2
                <InType, OutType, Epilogue>::Cutlass3xGemm >(
                out, a, e, b, std::forward<EpilogueArgs>(args)...);
        if (n == 28672 && k == 4096)
            return cutlass_sparse_gemm_caller<typename sm90_bf16_config_3
                <InType, OutType, Epilogue>::Cutlass3xGemm >(
                out, a, e, b, std::forward<EpilogueArgs>(args)...);
    } else if (m <= 16) {
        if (n == 4096 && k == 4096)
            return cutlass_sparse_gemm_caller<typename sm90_bf16_config_4
                <InType, OutType, Epilogue>::Cutlass3xGemm >(
                out, a, e, b, std::forward<EpilogueArgs>(args)...);
        if (n == 4096 && k == 14336)
            return cutlass_sparse_gemm_caller<typename sm90_bf16_config_5
                <InType, OutType, Epilogue>::Cutlass3xGemm >(
                out, a, e, b, std::forward<EpilogueArgs>(args)...);
        if (n == 6144 && k == 4096)
            return cutlass_sparse_gemm_caller<typename sm90_bf16_config_6
                <InType, OutType, Epilogue>::Cutlass3xGemm >(
                out, a, e, b, std::forward<EpilogueArgs>(args)...);
        if (n == 28672 && k == 4096)
            return cutlass_sparse_gemm_caller<typename sm90_bf16_config_7
                <InType, OutType, Epilogue>::Cutlass3xGemm >(
                out, a, e, b, std::forward<EpilogueArgs>(args)...);
    } else if (m <= 32) {
        if (n == 4096 && k == 4096)
            return cutlass_sparse_gemm_caller<typename sm90_bf16_config_8
                <InType, OutType, Epilogue>::Cutlass3xGemm >(
                out, a, e, b, std::forward<EpilogueArgs>(args)...);
        if (n == 4096 && k == 14336)
            return cutlass_sparse_gemm_caller<typename sm90_bf16_config_9
                <InType, OutType, Epilogue>::Cutlass3xGemm >(
                out, a, e, b, std::forward<EpilogueArgs>(args)...);
        if (n == 6144 && k == 4096)
            return cutlass_sparse_gemm_caller<typename sm90_bf16_config_10
                <InType, OutType, Epilogue>::Cutlass3xGemm >(
                out, a, e, b, std::forward<EpilogueArgs>(args)...);
        if (n == 28672 && k == 4096)
            return cutlass_sparse_gemm_caller<typename sm90_bf16_config_11
                <InType, OutType, Epilogue>::Cutlass3xGemm >(
                out, a, e, b, std::forward<EpilogueArgs>(args)...);
    } else if (m <= 64) {
        if (n == 4096 && k == 4096)
            return cutlass_sparse_gemm_caller<typename sm90_bf16_config_12
                <InType, OutType, Epilogue>::Cutlass3xGemm >(
                out, a, e, b, std::forward<EpilogueArgs>(args)...);
        if (n == 4096 && k == 14336)
            return cutlass_sparse_gemm_caller<typename sm90_bf16_config_13
                <InType, OutType, Epilogue>::Cutlass3xGemm >(
                out, a, e, b, std::forward<EpilogueArgs>(args)...);
        if (n == 6144 && k == 4096)
            return cutlass_sparse_gemm_caller<typename sm90_bf16_config_14
                <InType, OutType, Epilogue>::Cutlass3xGemm >(
                out, a, e, b, std::forward<EpilogueArgs>(args)...);
        if (n == 28672 && k == 4096)
            return cutlass_sparse_gemm_caller<typename sm90_bf16_config_15
                <InType, OutType, Epilogue>::Cutlass3xGemm >(
                out, a, e, b, std::forward<EpilogueArgs>(args)...);
    } else if (m <= 128) {
        if (n == 4096 && k == 4096)
            return cutlass_sparse_gemm_caller<typename sm90_bf16_config_16
                <InType, OutType, Epilogue>::Cutlass3xGemm >(
                out, a, e, b, std::forward<EpilogueArgs>(args)...);
        if (n == 4096 && k == 14336)
            return cutlass_sparse_gemm_caller<typename sm90_bf16_config_17
                <InType, OutType, Epilogue>::Cutlass3xGemm >(
                out, a, e, b, std::forward<EpilogueArgs>(args)...);
        if (n == 6144 && k == 4096)
            return cutlass_sparse_gemm_caller<typename sm90_bf16_config_18
                <InType, OutType, Epilogue>::Cutlass3xGemm >(
                out, a, e, b, std::forward<EpilogueArgs>(args)...);
        if (n == 28672 && k == 4096)
            return cutlass_sparse_gemm_caller<typename sm90_bf16_config_19
                <InType, OutType, Epilogue>::Cutlass3xGemm >(
                out, a, e, b, std::forward<EpilogueArgs>(args)...);
    } else if (m <= 256) {
        if (n == 4096 && k == 4096)
            return cutlass_sparse_gemm_caller<typename sm90_bf16_config_20
                <InType, OutType, Epilogue>::Cutlass3xGemm >(
                out, a, e, b, std::forward<EpilogueArgs>(args)...);
        if (n == 4096 && k == 14336)
            return cutlass_sparse_gemm_caller<typename sm90_bf16_config_21
                <InType, OutType, Epilogue>::Cutlass3xGemm >(
                out, a, e, b, std::forward<EpilogueArgs>(args)...);
        if (n == 6144 && k == 4096)
            return cutlass_sparse_gemm_caller<typename sm90_bf16_config_22
                <InType, OutType, Epilogue>::Cutlass3xGemm >(
                out, a, e, b, std::forward<EpilogueArgs>(args)...);
        if (n == 28672 && k == 4096)
            return cutlass_sparse_gemm_caller<typename sm90_bf16_config_23
                <InType, OutType, Epilogue>::Cutlass3xGemm >(
                out, a, e, b, std::forward<EpilogueArgs>(args)...);
    } else { // m512 kernels
        if (n == 4096 && k == 4096)
            return cutlass_sparse_gemm_caller<typename sm90_bf16_config_24
                <InType, OutType, Epilogue>::Cutlass3xGemm >(
                out, a, e, b, std::forward<EpilogueArgs>(args)...);
        if (n == 4096 && k == 14336)
            return cutlass_sparse_gemm_caller<typename sm90_bf16_config_25
                <InType, OutType, Epilogue>::Cutlass3xGemm >(
                out, a, e, b, std::forward<EpilogueArgs>(args)...);
        if (n == 6144 && k == 4096)
            return cutlass_sparse_gemm_caller<typename sm90_bf16_config_26
                <InType, OutType, Epilogue>::Cutlass3xGemm >(
                out, a, e, b, std::forward<EpilogueArgs>(args)...);
        if (n == 28672 && k == 4096)
            return cutlass_sparse_gemm_caller<typename sm90_bf16_config_27
                <InType, OutType, Epilogue>::Cutlass3xGemm >(
                out, a, e, b, std::forward<EpilogueArgs>(args)...);
    }

  using Cutlass3xGemmDefault =
      typename sm90_bf16_config_default<InType, OutType,
                                       Epilogue>::Cutlass3xGemm;

    // m in (128, inf)
    return cutlass_sparse_gemm_caller<Cutlass3xGemmDefault>(
        out, a, e, b, std::forward<EpilogueArgs>(args)...);
}

template <typename InType, typename OutType,
          template <typename, typename, typename> typename Epilogue,
          typename... EpilogueArgs>
void cutlass_gemm_sm90_int8_dispatch(torch::Tensor& out, torch::Tensor const& a,
                                     torch::Tensor const& e,
                                     torch::Tensor const& b,
                                     EpilogueArgs&&... args) {
  static_assert(std::is_same<InType, int8_t>());
  TORCH_CHECK(a.dtype() == torch::kInt8);
  TORCH_CHECK(e.dtype() == torch::kUInt8);
  TORCH_CHECK(b.dtype() == torch::kInt8);

  uint32_t const m = out.size(1);
  uint32_t const n = out.size(0);
  uint32_t const k = b.size(0);

  if (m == 1) {
      if (n == 4096 && k == 4096)
          return cutlass_sparse_gemm_caller<typename sm90_int8_config_0
              <InType, OutType, Epilogue>::Cutlass3xGemm >(
              out, a, e, b, std::forward<EpilogueArgs>(args)...);
      if (n == 4096 && k == 14336)
          return cutlass_sparse_gemm_caller<typename sm90_int8_config_1
              <InType, OutType, Epilogue>::Cutlass3xGemm >(
              out, a, e, b, std::forward<EpilogueArgs>(args)...);
      if (n == 6144 && k == 4096)
          return cutlass_sparse_gemm_caller<typename sm90_int8_config_2
              <InType, OutType, Epilogue>::Cutlass3xGemm >(
              out, a, e, b, std::forward<EpilogueArgs>(args)...);
      if (n == 28672 && k == 4096)
          return cutlass_sparse_gemm_caller<typename sm90_int8_config_3
              <InType, OutType, Epilogue>::Cutlass3xGemm >(
              out, a, e, b, std::forward<EpilogueArgs>(args)...);
  } else if (m <= 16) {
      if (n == 4096 && k == 4096)
          return cutlass_sparse_gemm_caller<typename sm90_int8_config_4
              <InType, OutType, Epilogue>::Cutlass3xGemm >(
              out, a, e, b, std::forward<EpilogueArgs>(args)...);
      if (n == 4096 && k == 14336)
          return cutlass_sparse_gemm_caller<typename sm90_int8_config_5
              <InType, OutType, Epilogue>::Cutlass3xGemm >(
              out, a, e, b, std::forward<EpilogueArgs>(args)...);
      if (n == 6144 && k == 4096)
          return cutlass_sparse_gemm_caller<typename sm90_int8_config_6
              <InType, OutType, Epilogue>::Cutlass3xGemm >(
              out, a, e, b, std::forward<EpilogueArgs>(args)...);
      if (n == 28672 && k == 4096)
          return cutlass_sparse_gemm_caller<typename sm90_int8_config_7
              <InType, OutType, Epilogue>::Cutlass3xGemm >(
              out, a, e, b, std::forward<EpilogueArgs>(args)...);
  } else if (m <= 32) {
      if (n == 4096 && k == 4096)
          return cutlass_sparse_gemm_caller<typename sm90_int8_config_8
              <InType, OutType, Epilogue>::Cutlass3xGemm >(
              out, a, e, b, std::forward<EpilogueArgs>(args)...);
      if (n == 4096 && k == 14336)
          return cutlass_sparse_gemm_caller<typename sm90_int8_config_9
              <InType, OutType, Epilogue>::Cutlass3xGemm >(
              out, a, e, b, std::forward<EpilogueArgs>(args)...);
      if (n == 6144 && k == 4096)
          return cutlass_sparse_gemm_caller<typename sm90_int8_config_10
              <InType, OutType, Epilogue>::Cutlass3xGemm >(
              out, a, e, b, std::forward<EpilogueArgs>(args)...);
      if (n == 28672 && k == 4096)
          return cutlass_sparse_gemm_caller<typename sm90_int8_config_11
              <InType, OutType, Epilogue>::Cutlass3xGemm >(
              out, a, e, b, std::forward<EpilogueArgs>(args)...);
  } else if (m <= 64) {
      if (n == 4096 && k == 4096)
          return cutlass_sparse_gemm_caller<typename sm90_int8_config_12
              <InType, OutType, Epilogue>::Cutlass3xGemm >(
              out, a, e, b, std::forward<EpilogueArgs>(args)...);
      if (n == 4096 && k == 14336)
          return cutlass_sparse_gemm_caller<typename sm90_int8_config_13
              <InType, OutType, Epilogue>::Cutlass3xGemm >(
              out, a, e, b, std::forward<EpilogueArgs>(args)...);
      if (n == 6144 && k == 4096)
          return cutlass_sparse_gemm_caller<typename sm90_int8_config_14
              <InType, OutType, Epilogue>::Cutlass3xGemm >(
              out, a, e, b, std::forward<EpilogueArgs>(args)...);
      if (n == 28672 && k == 4096)
          return cutlass_sparse_gemm_caller<typename sm90_int8_config_15
              <InType, OutType, Epilogue>::Cutlass3xGemm >(
              out, a, e, b, std::forward<EpilogueArgs>(args)...);
  } else if (m <= 128) {
      if (n == 4096 && k == 4096)
          return cutlass_sparse_gemm_caller<typename sm90_int8_config_16
              <InType, OutType, Epilogue>::Cutlass3xGemm >(
              out, a, e, b, std::forward<EpilogueArgs>(args)...);
      if (n == 4096 && k == 14336)
          return cutlass_sparse_gemm_caller<typename sm90_int8_config_17
              <InType, OutType, Epilogue>::Cutlass3xGemm >(
              out, a, e, b, std::forward<EpilogueArgs>(args)...);
      if (n == 6144 && k == 4096)
          return cutlass_sparse_gemm_caller<typename sm90_int8_config_18
              <InType, OutType, Epilogue>::Cutlass3xGemm >(
              out, a, e, b, std::forward<EpilogueArgs>(args)...);
      if (n == 28672 && k == 4096)
          return cutlass_sparse_gemm_caller<typename sm90_int8_config_19
              <InType, OutType, Epilogue>::Cutlass3xGemm >(
              out, a, e, b, std::forward<EpilogueArgs>(args)...);
  } else if (m <= 256) {
      if (n == 4096 && k == 4096)
          return cutlass_sparse_gemm_caller<typename sm90_int8_config_20
              <InType, OutType, Epilogue>::Cutlass3xGemm >(
              out, a, e, b, std::forward<EpilogueArgs>(args)...);
      if (n == 4096 && k == 14336)
          return cutlass_sparse_gemm_caller<typename sm90_int8_config_21
              <InType, OutType, Epilogue>::Cutlass3xGemm >(
              out, a, e, b, std::forward<EpilogueArgs>(args)...);
      if (n == 6144 && k == 4096)
          return cutlass_sparse_gemm_caller<typename sm90_int8_config_22
              <InType, OutType, Epilogue>::Cutlass3xGemm >(
              out, a, e, b, std::forward<EpilogueArgs>(args)...);
      if (n == 28672 && k == 4096)
          return cutlass_sparse_gemm_caller<typename sm90_int8_config_23
              <InType, OutType, Epilogue>::Cutlass3xGemm >(
              out, a, e, b, std::forward<EpilogueArgs>(args)...);
  } else { // m512 kernels
      if (n == 4096 && k == 4096)
          return cutlass_sparse_gemm_caller<typename sm90_int8_config_24
              <InType, OutType, Epilogue>::Cutlass3xGemm >(
              out, a, e, b, std::forward<EpilogueArgs>(args)...);
      if (n == 4096 && k == 14336)
          return cutlass_sparse_gemm_caller<typename sm90_int8_config_25
              <InType, OutType, Epilogue>::Cutlass3xGemm >(
              out, a, e, b, std::forward<EpilogueArgs>(args)...);
      if (n == 6144 && k == 4096)
          return cutlass_sparse_gemm_caller<typename sm90_int8_config_26
              <InType, OutType, Epilogue>::Cutlass3xGemm >(
              out, a, e, b, std::forward<EpilogueArgs>(args)...);
      if (n == 28672 && k == 4096)
          return cutlass_sparse_gemm_caller<typename sm90_int8_config_27
              <InType, OutType, Epilogue>::Cutlass3xGemm >(
              out, a, e, b, std::forward<EpilogueArgs>(args)...);
  }

  using Cutlass3xGemmDefault =
      typename sm90_int8_config_default<InType, OutType,
                                        Epilogue>::Cutlass3xGemm;
  using Cutlass3xGemmM128 =
      typename sm90_int8_config_M128<InType, OutType, Epilogue>::Cutlass3xGemm;
  using Cutlass3xGemmM64 =
      typename sm90_int8_config_M64<InType, OutType, Epilogue>::Cutlass3xGemm;
  using Cutlass3xGemmM32NBig =
      typename sm90_int8_config_M32_NBig<InType, OutType,
                                         Epilogue>::Cutlass3xGemm;
  using Cutlass3xGemmM32NSmall =
      typename sm90_int8_config_M32_NSmall<InType, OutType,
                                           Epilogue>::Cutlass3xGemm;

  bool const is_small_n = n < 8192;

  uint32_t const mp2 =
      std::max(static_cast<uint32_t>(32), next_pow_2(m));  // next power of 2

  if (mp2 <= 32) {
    // m in [1, 32]
    if (is_small_n) {
      return cutlass_sparse_gemm_caller<Cutlass3xGemmM32NSmall>(
          out, a, e, b, std::forward<EpilogueArgs>(args)...);
    } else {
      return cutlass_sparse_gemm_caller<Cutlass3xGemmM32NBig>(
          out, a, e, b, std::forward<EpilogueArgs>(args)...);
    }
  } else if (mp2 <= 64) {
    // m in (32, 64]
    return cutlass_sparse_gemm_caller<Cutlass3xGemmM64>(
        out, a, e, b, std::forward<EpilogueArgs>(args)...);
  } else if (mp2 <= 128) {
    // m in (64, 128]
    return cutlass_sparse_gemm_caller<Cutlass3xGemmM128>(
        out, a, e, b, std::forward<EpilogueArgs>(args)...);
  } else {
    // m in (128, inf)
    return cutlass_sparse_gemm_caller<Cutlass3xGemmDefault>(
        out, a, e, b, std::forward<EpilogueArgs>(args)...);
  }
}

template <template <typename, typename, typename> typename Epilogue,
          typename... EpilogueArgs>
void cutlass_scaled_sparse_mm_sm90_epilogue(torch::Tensor& out, torch::Tensor const& a,
                                     torch::Tensor const& e,
                                     torch::Tensor const& b,
                                     EpilogueArgs&&... epilogue_args) {
  TORCH_CHECK(e.dtype() == torch::kUInt8);
  if (a.dtype() == torch::kInt8) {
    TORCH_CHECK(b.dtype() == torch::kInt8);

    if (out.dtype() == torch::kBFloat16) {
      return cutlass_gemm_sm90_int8_dispatch<int8_t, cutlass::bfloat16_t,
                                             Epilogue>(
          out, a, e, b, std::forward<EpilogueArgs>(epilogue_args)...);
    } else {
      TORCH_CHECK(out.dtype() == torch::kFloat16);
      return cutlass_gemm_sm90_int8_dispatch<int8_t, cutlass::half_t, Epilogue>(
          out, a, e, b, std::forward<EpilogueArgs>(epilogue_args)...);
    }
  } else if (a.dtype() == torch::kFloat8_e4m3fn) {
    TORCH_CHECK(b.dtype() == torch::kFloat8_e4m3fn);

    if (out.dtype() == torch::kBFloat16) {
      return cutlass_gemm_sm90_fp8_dispatch<cutlass::float_e4m3_t,
                                            cutlass::bfloat16_t, Epilogue>(
          out, a, e, b, std::forward<EpilogueArgs>(epilogue_args)...);
    } else {
      TORCH_CHECK(out.dtype() == torch::kFloat16);
      return cutlass_gemm_sm90_fp8_dispatch<cutlass::float_e4m3_t,
                                            cutlass::half_t, Epilogue>(
          out, a, e, b, std::forward<EpilogueArgs>(epilogue_args)...);
    }
  }
  else if (a.dtype() == torch::kFloat16) {
    TORCH_CHECK(b.dtype() == torch::kFloat16);

    if (out.dtype() == torch::kBFloat16) {
      return cutlass_gemm_sm90_fp16_dispatch<cutlass::half_t,
                                            cutlass::bfloat16_t, Epilogue>(
          out, a, e, b, std::forward<EpilogueArgs>(epilogue_args)...);
    } else {
      TORCH_CHECK(out.dtype() == torch::kFloat16);
      return cutlass_gemm_sm90_fp16_dispatch<cutlass::half_t,
                                            cutlass::half_t, Epilogue>(
          out, a, e, b, std::forward<EpilogueArgs>(epilogue_args)...);
    }
  }
  else { // a.dtype() == torch::kBFloat16
    TORCH_CHECK(a.dtype() == torch::kBFloat16);
    TORCH_CHECK(b.dtype() == torch::kBFloat16);

    if (out.dtype() == torch::kBFloat16) {
      return cutlass_gemm_sm90_bf16_dispatch<cutlass::bfloat16_t,
                                            cutlass::bfloat16_t, Epilogue>(
          out, a, e, b, std::forward<EpilogueArgs>(epilogue_args)...);
    } else {
      TORCH_CHECK(out.dtype() == torch::kFloat16);
      return cutlass_gemm_sm90_bf16_dispatch<cutlass::bfloat16_t,
                                            cutlass::half_t, Epilogue>(
          out, a, e, b, std::forward<EpilogueArgs>(epilogue_args)...);
    }
  }
}

void cutlass_scaled_sparse_mm_sm90(torch::Tensor& c, torch::Tensor const& a,
                            torch::Tensor const& e,
                            torch::Tensor const& b,
                            torch::Tensor const& a_scales,
                            torch::Tensor const& b_scales,
                            c10::optional<torch::Tensor> const& bias) {
  TORCH_CHECK(a_scales.dtype() == torch::kFloat32);
  TORCH_CHECK(b_scales.dtype() == torch::kFloat32);
  if (bias) {
    TORCH_CHECK(bias->dtype() == c.dtype(),
                "currently bias dtype must match output dtype ", c.dtype());
    return cutlass_scaled_sparse_mm_sm90_epilogue<ScaledEpilogueBias>(
        c, a, e, b, a_scales, b_scales, *bias);
  } else {
    return cutlass_scaled_sparse_mm_sm90_epilogue<ScaledEpilogue>(c, a, e, b,
                                                           a_scales,
                                                           b_scales);
  }
}

void cutlass_scaled_sparse_mm_azp_sm90(torch::Tensor& out, torch::Tensor const& a,
                                torch::Tensor const& e,
                                torch::Tensor const& b,
                                torch::Tensor const& a_scales,
                                torch::Tensor const& b_scales,
                                torch::Tensor const& azp_adj,
                                c10::optional<torch::Tensor> const& azp,
                                c10::optional<torch::Tensor> const& bias) {
  TORCH_CHECK(a_scales.dtype() == torch::kFloat32);
  TORCH_CHECK(b_scales.dtype() == torch::kFloat32);

  if (azp) {
    return cutlass_scaled_sparse_mm_sm90_epilogue<ScaledEpilogueBiasAzpToken>(
        out, a, e, b, a_scales, b_scales, azp_adj, *azp, bias);
  } else {
    return cutlass_scaled_sparse_mm_sm90_epilogue<ScaledEpilogueBiasAzp>(
        out, a, e, b, a_scales, b_scales, azp_adj, bias);
  }
}

#endif
