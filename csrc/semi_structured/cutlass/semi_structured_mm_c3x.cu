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

#include "broadcast_load_epilogue_c3x.hpp"
#include "common.hpp"
// clang-format on

using namespace cute;

/*
   This file defines quantized GEMM operations using the CUTLASS 3.x API, for
   NVIDIA GPUs with sm90a (Hopper) or later.

   Epilogue functions can be defined to post-process the output before it is
   written to GPU memory.
   Epilogues must contain a public type named EVTCompute of type Sm90EVT,
   as well as a static prepare_args function that constructs an
   EVTCompute::Arguments struct.
*/

namespace {

template <typename ElementAB_, typename ElementD_,
          typename TileShape, typename ClusterShape, typename KernelSchedule,
          typename EpilogueSchedule>
struct cutlass_3x_sparse_gemm {
  using ElementAB = ElementAB_;
  using ElementD = ElementD_;
  // using ElementAcc =
  //     typename std::conditional<std::is_same_v<ElementAB, int8_t>, int32_t,
  //                               float>::type;
  using ElementAcc = ElementD;

  using StrideD = Stride<int64_t, Int<1>, Int<0>>;
  using ElementC = void;
  constexpr int AlignmentC  = 128 / cutlass::sizeof_bits<ElementC>::value;
  using LayoutTagC  = cutlass::layout::ColumnMajor;
  using StrideC = StrideD;

  constexpr int AlignmentAB  = 128 / cutlass::sizeof_bits<ElementAB>::value;

  // using CollectiveEpilogue =
  //     typename cutlass::epilogue::collective::CollectiveBuilder<
  //         cutlass::arch::Sm90, cutlass::arch::OpClassTensorOp, TileShape,
  //         ClusterShape, cutlass::epilogue::collective::EpilogueTileAuto,
  //         ElementAcc, float, ElementC, StrideC, 4, ElementD, StrideD, 4,
  //         EpilogueSchedule, EVTCompute>::CollectiveOp;
  
  using CollectiveEpilogue = typename cutlass::epilogue::collective::CollectiveBuilder<
    cutlass::arch::Sm90, cutlass::arch::OpClassTensorOp,
    TileShape, ClusterShape,
    cutlass::epilogue::collective::EpilogueTileAuto,
    ElementAcc, ElementAcc,
    ElementC, LayoutTagC, AlignmentC,
    ElementD, LayoutTagC, AlignmentC,
    EpilogueSchedule
  >::CollectiveOp;

  // static constexpr size_t CEStorageSize =
  //     sizeof(typename CollectiveEpilogue::SharedStorage);
  // using Stages = typename cutlass::gemm::collective::StageCountAutoCarveout<
  //     static_cast<int>(CEStorageSize)>;

  // using CollectiveMainloop =
  //     typename cutlass::gemm::collective::CollectiveBuilder<
  //         cutlass::arch::Sm90, cutlass::arch::OpClassTensorOp, 
  //         ElementAB, cutlass::layout::RowMajor, 16, 
  //         ElementAB, cutlass::layout::ColumnMajor, 16, 
  //         ElementAcc, TileShape, ClusterShape,
  //         Stages,
  //         KernelSchedule>::CollectiveOp;

  using CollectiveMainloop = typename cutlass::gemm::collective::CollectiveBuilder<
    // cutlass::arch::Sm90, cutlass::arch::OpClassSparseTensorOp,
    cutlass::arch::Sm90, cutlass::arch::OpClassTensorOp,
    ElementAB, cutlass::layout::RowMajor, AlignmentAB,
    ElementAB, cutlass::layout::ColumnMajor, AlignmentAB,
    ElementAcc,
    TileShape, ClusterShape,
    cutlass::gemm::collective::StageCountAutoCarveout<
      static_cast<int>(sizeof(typename CollectiveEpilogue::SharedStorage))
    >,
    KernelSchedule
  >::CollectiveOp;

  // using KernelType = enable_sm90_or_later<cutlass::gemm::kernel::GemmUniversal<
  //     cute::Shape<int, int, int, int>, CollectiveMainloop, CollectiveEpilogue,
  //     cutlass::gemm::PersistentScheduler>>;
  
  using GemmKernel = cutlass::gemm::kernel::GemmUniversal<
    cute::Shape<int, int, int, int>,
    CollectiveMainloop,
    CollectiveEpilogue
>;

  struct GemmKernel : public KernelType {};
};

template <typename Gemm>
void cutlass_gemm_caller(torch::Tensor& out, torch::Tensor const& a,
                         torch::Tensor const& b) {
  using ElementAB = typename Gemm::ElementAB;
  using ElementD = typename Gemm::ElementD;

  int32_t m = a.size(0);
  int32_t n = b.size(1);
  int32_t k = a.size(1);

  int64_t lda = a.stride(0);
  int64_t ldb = b.stride(1);
  int64_t ldc = out.stride(0);

  using StrideA = Stride<int64_t, Int<1>, int64_t>;
  using StrideB = Stride<int64_t, Int<1>, int64_t>;
  using StrideC = typename Gemm::StrideC;

  StrideA a_stride{lda, Int<1>{}, 0};
  StrideB b_stride{ldb, Int<1>{}, 0};
  StrideC c_stride{ldc, Int<1>{}, Int<0>{}};

  using GemmKernel = typename Gemm::GemmKernel;
  typename GemmKernel::ProblemShape prob_shape{m, n, k, 1};

  auto a_ptr = static_cast<ElementAB*>(a.data_ptr());
  auto b_ptr = static_cast<ElementAB*>(b.data_ptr());
  typename GemmKernel::MainloopArguments mainloop_args{a_ptr, a_stride, b_ptr,
                                                       b_stride};

  auto c_ptr = static_cast<ElementD*>(out.data_ptr());
  // typename GemmKernel::EpilogueArguments epilogue_args{
  //     Gemm::Epilogue::prepare_args(
  //         std::forward<EpilogueArgs>(epilogue_params)...),
  //     c_ptr, c_stride, c_ptr, c_stride};

  typename GemmKernel::Arguments args{cutlass::gemm::GemmUniversalMode::kGemm,
                                      prob_shape, mainloop_args, epilogue_args};

  // Launch the CUTLASS GEMM kernel.
  using GemmOp = cutlass::gemm::device::GemmUniversalAdapter<GemmKernel>;
  GemmOp gemm_op;
  CUTLASS_CHECK(gemm_op.can_implement(args));

  size_t workspace_size = gemm_op.get_workspace_size(args);
  auto const workspace_options =
      torch::TensorOptions().dtype(torch::kUInt8).device(a.device());
  auto workspace = torch::empty(workspace_size, workspace_options);

  auto stream = at::cuda::getCurrentCUDAStream(a.get_device());

  cutlass::Status status = gemm_op.run(args, workspace.data_ptr(), stream);
  CUTLASS_CHECK(status);
}

template <typename InType, typename OutType>
struct sm90_fp8_config_default {
  // M in (128, inf)
  static_assert(std::is_same<InType, cutlass::float_e4m3_t>());
  using KernelSchedule =
      cutlass::gemm::KernelTmaWarpSpecialized;
  using EpilogueSchedule = cutlass::epilogue::TmaWarpSpecialized;
  using TileShape = Shape<_128, _128, _128>;
  using ClusterShape = Shape<_1, _2, _1>;
  using Cutlass3xGemm =
      cutlass_3x_sparse_gemm<InType, OutType, TileShape, ClusterShape,
                      KernelSchedule, EpilogueSchedule>;
};

}  // namespace

template <typename InType, typename OutType>
void cutlass_gemm_sm90_fp8_dispatch(torch::Tensor& out, torch::Tensor const& a,
                                    torch::Tensor const& b) {
  static_assert(std::is_same<InType, cutlass::float_e4m3_t>());
  TORCH_CHECK(a.dtype() == torch::kFloat8_e4m3fn);
  TORCH_CHECK(b.dtype() == torch::kFloat8_e4m3fn);

  using Cutlass3xGemmDefault =
      typename sm90_fp8_config_default<InType, OutType>::Cutlass3xGemm;

  return cutlass_gemm_caller<Cutlass3xGemmDefault>(out, a, b);
}

void cutlass_semi_structured_mm_sm90(torch::Tensor& out, torch::Tensor const& a,
                                     torch::Tensor const& b) {
  TORCH_CHECK(a.dtype() == torch::kFloat8_e4m3fn);
  TORCH_CHECK(b.dtype() == torch::kFloat8_e4m3fn);

  if (out.dtype() == torch::kBFloat16) {
      return cutlass_gemm_sm90_fp8_dispatch<cutlass::float_e4m3_t,
                                          cutlass::bfloat16_t>(
          out, a, b);
  } else {
      TORCH_CHECK(out.dtype() == torch::kFloat16);
      return cutlass_gemm_sm90_fp8_dispatch<cutlass::float_e4m3_t,
                                          cutlass::half_t>(
          out, a, b);
  }
  // TODO: Add other data types
}

#endif
