/* Copyright 2020 Stanford
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#include "model.h"
#include "cuda_helper.h"

Tensor FFModel::add(std::string name,
                    const Tensor& in1,
                    const Tensor& in2)
{
  ElementBinary *ele = new ElementBinary(*this, ElementBinary::OP_ADD, name, in1, in2);
  ele->add_to_model(*this);
  return ele->output;
}

ElementBinary* FFModel::add(std::string name)
{
  ElementBinary* ele = new ElementBinary(*this, ElementBinary::OP_ADD, name);
  return ele;
}

Tensor FFModel::subtract(std::string name,
                         const Tensor& in1,
                         const Tensor& in2)
{
  ElementBinary *ele = new ElementBinary(*this, ElementBinary::OP_SUB, name, in1, in2);
  ele->add_to_model(*this);
  return ele->output;
}

ElementBinary* FFModel::subtract(std::string name)
{
  ElementBinary* ele = new ElementBinary(*this, ElementBinary::OP_SUB, name);
  return ele;
}

Tensor FFModel::multiply(std::string name,
                         const Tensor& in1,
                         const Tensor& in2)
{
  ElementBinary *ele = new ElementBinary(*this, ElementBinary::OP_MUL, name, in1, in2);
  ele->add_to_model(*this);
  return ele->output;
}

ElementBinary* FFModel::multiply(std::string name)
{
  ElementBinary* ele = new ElementBinary(*this, ElementBinary::OP_MUL, name);
  return ele;
}

Tensor FFModel::divide(std::string name,
                       const Tensor& in1,
                       const Tensor& in2)
{
  ElementBinary *ele = new ElementBinary(*this, ElementBinary::OP_DIV, name, in1, in2);
  ele->add_to_model(*this);
  return ele->output;
}

ElementBinary* FFModel::divide(std::string name)
{
  ElementBinary* ele = new ElementBinary(*this, ElementBinary::OP_DIV, name);
  return ele;
}

ElementBinary::ElementBinary(FFModel& model,
                             ElementBinary::OpType _op_type,
                             const std::string& pcname,
                             const Tensor& in1,
                             const Tensor& in2)
: Op(pcname, in1, in2), op_type(_op_type)
{
  //TODO: implement broadcast op
  assert(in1.numDim == in2.numDim);
  int dim = in1.numDim;
  for (int i = 0; i < dim; i++)
    assert(in1.adim[i] == in2.adim[i]);
  switch (dim) {
    case 1:
    {
      task_is = model.get_or_create_task_is(1, name);
      create_output_and_partition<1>(model);
      break;
    }
    case 2:
    {
      task_is = model.get_or_create_task_is(2, name);
      create_output_and_partition<2>(model);
      break;
    }
    case 3:
    {
      task_is = model.get_or_create_task_is(3, name);
      create_output_and_partition<3>(model);
      break;
    }
    case 4:
    {
      task_is = model.get_or_create_task_is(4, name);
      create_output_and_partition<4>(model);
      break;
    }
    default:
    {
      // Unsupported dim for ElementBinarywise operator
      assert(false);
    }
  }
}

ElementBinary::ElementBinary(FFModel& model,
                             ElementBinary::OpType _op_type,
                             const std::string& pcname)
: Op(pcname), op_type(_op_type)
{
}

Tensor ElementBinary::init_inout(FFModel& model,
                           const Tensor& input)
{
  // TODO: currently disable this functional API since
  // FlexFlow assumes a single tensor as input
  assert(false);
  Tensor in1 = input, in2 = input;
  add_to_model(model);
  inputs[0] = in1;
  inputs[1] = in2;
  //TODO: implement broadcast op
  assert(in1.numDim == in2.numDim);
  int dim = in1.numDim;
  for (int i = 0; i < dim; i++)
    assert(in1.adim[i] == in2.adim[i]);
  switch (dim) {
    case 1:
    {
      task_is = model.get_or_create_task_is(1, name);
      create_output_and_partition<1>(model);
      break;
    }
    case 2:
    {
      task_is = model.get_or_create_task_is(2, name);
      create_output_and_partition<2>(model);
      break;
    }
    case 3:
    {
      task_is = model.get_or_create_task_is(3, name);
      create_output_and_partition<3>(model);
      break;
    }
    case 4:
    {
      task_is = model.get_or_create_task_is(4, name);
      create_output_and_partition<4>(model);
      break;
    }
    default:
    {
      // Unsupported dim for ElementWiseBinary operator
      assert(false);
    }
  }
  return output;
}

void ElementBinary::add_to_model(FFModel& model)
{
  model.layers.push_back(this);
}

template<int NDIM>
void ElementBinary::create_output_and_partition(FFModel& model)
{
  // Retrive the task indexspace for the op
  task_is = IndexSpaceT<NDIM>(model.get_or_create_task_is(NDIM, name));
  Context ctx = model.config.lg_ctx;
  Runtime* runtime = model.config.lg_hlr;
  Rect<NDIM> part_rect = runtime->get_index_space_domain(ctx, task_is);
  int dims[NDIM];
  for (int i = 0; i < NDIM; i++)
    dims[i] = inputs[0].adim[NDIM-1-i];
  output = model.create_tensor<NDIM>(dims, IndexSpaceT<NDIM>(task_is), DT_FLOAT);
  Rect<NDIM> input_rect;
  for (int i = 0; i < 2; i++) {
    input_rect = runtime->get_index_partition_color_space(
        ctx, inputs[i].part.get_index_partition());
    if (input_rect == part_rect) {
      input_lps[i] = inputs[i].part;
      input_grad_lps[i] = inputs[i].part_grad;
    } else {
      model.create_disjoint_partition<NDIM>(
          inputs[i], IndexSpaceT<NDIM>(task_is), input_lps[i], input_grad_lps[i]);
    }
  }
}

void ElementBinary::init(const FFModel& ff)
{
}

__global__
void elewise_binary_forward_kernel(coord_t volume,
                                 ElementBinary::OpType type,
                                 const float* in1,
                                 const float* in2,
                                 float* out)
{
  CUDA_KERNEL_LOOP(i, volume)
  {
    switch (type) {
      case ElementBinary::OP_ADD:
      {
        out[i] = in1[i] + in2[i];
        break;
      }
      case ElementBinary::OP_SUB:
      {
        out[i] = in1[i] - in2[i];
        break;
      }
      case ElementBinary::OP_MUL:
      {
        out[i] = in1[i] * in2[i];
        break;
      }
      case ElementBinary::OP_DIV:
      {
        out[i] = in1[i] / in2[i];
        break;
      }
      default:
        assert(false);
    }
  }
}

/*
  regions[0](I): in1
  regions[1](I): in2
  regions[2](O): output
*/
__host__
void ElementBinary::forward_task(const Task* task,
                                 const std::vector<PhysicalRegion> &regions,
                                 Context ctx, Runtime* runtime)
{
  assert(regions.size() == 3);
  assert(task->regions.size() == 3);
  const ElementBinary* ele = (const ElementBinary*) task->args;
  Domain in1_domain = runtime->get_index_space_domain(
    ctx, task->regions[0].region.get_index_space());
  Domain in2_domain = runtime->get_index_space_domain(
    ctx, task->regions[1].region.get_index_space());
  Domain out_domain = runtime->get_index_space_domain(
    ctx, task->regions[2].region.get_index_space());
  assert(in1_domain == in2_domain);
  assert(out_domain == in1_domain);

  const float* in1_ptr = helperGetTensorPointerR<float>(
    regions[0], task->regions[0], FID_DATA, ctx, runtime);
  const float* in2_ptr = helperGetTensorPointerR<float>(
    regions[1], task->regions[1], FID_DATA, ctx, runtime);
  float* out_ptr = helperGetTensorPointerWO<float>(
    regions[2], task->regions[2], FID_DATA, ctx, runtime);
  elewise_binary_forward_kernel<<<GET_BLOCKS(out_domain.get_volume()), CUDA_NUM_THREADS>>>(
  out_domain.get_volume(), ele->op_type, in1_ptr, in2_ptr, out_ptr);
}

void ElementBinary::forward(const FFModel& ff)
{
  ArgumentMap argmap;
  Context ctx = ff.config.lg_ctx;
  Runtime* runtime = ff.config.lg_hlr;
  IndexLauncher launcher(ELEMENTBINARY_FWD_TASK_ID, task_is,
                         TaskArgument(this, sizeof(ElementBinary)), argmap,
                         Predicate::TRUE_PRED, false/*must*/, 0/*mapper_id*/,
                         FFConfig::get_hash_id(std::string(name)));
  launcher.add_region_requirement(
    RegionRequirement(input_lps[0], 0/*projection id*/,
      READ_ONLY, EXCLUSIVE, inputs[0].region));
  launcher.add_field(0, FID_DATA);
  launcher.add_region_requirement(
    RegionRequirement(input_lps[1], 0/*projection id*/,
      READ_ONLY, EXCLUSIVE, inputs[1].region));
  launcher.add_field(1, FID_DATA);
  launcher.add_region_requirement(
    RegionRequirement(output.part, 0/*projection id*/,
      WRITE_ONLY, EXCLUSIVE, output.region));
  launcher.add_field(2, FID_DATA);
  runtime->execute_index_space(ctx, launcher);
}

__global__
void elewise_binary_backward_kernel(coord_t volume,
                                    ElementBinary::OpType type,
                                    const float* out_grad,
                                    const float* in1,
                                    const float* in2,
                                    float* in1_grad,
                                    float* in2_grad)
{
  CUDA_KERNEL_LOOP(i, volume)
  {
    switch (type) {
      case ElementBinary::OP_ADD:
      {
        in1_grad[i] = out_grad[i];
        in2_grad[i] = out_grad[i];
        break;
      }
      case ElementBinary::OP_SUB:
      {
        in1_grad[i] = out_grad[i];
        in2_grad[i] = -out_grad[i];
        break;
      }
      case ElementBinary::OP_MUL:
      {
        in1_grad[i] = out_grad[i] * in2[i];
        in2_grad[i] = out_grad[i] * in1[i];
        break;
      }
      case ElementBinary::OP_DIV:
      {
        in1_grad[i] = out_grad[i] / in2[i];
        in2_grad[i] = - out_grad[i] * in1[i] / (in2[i] * in2[i]);
        break;
      }
      default:
        assert(false);
    }
  }
}
/*
  regions[0](I): out_grad
  regions[1](I): in0
  regions[2](I): in1
  regions[3](O): in0_grad
  regions[4](O): in1_grad
*/
void ElementBinary::backward_task(const Task *task,
                            const std::vector<PhysicalRegion> &regions,
                            Context ctx, Runtime* runtime)
{
  const ElementBinary* ele = (const ElementBinary*) task->args;
  assert(regions.size() == 3);
  assert(task->regions.size() == 3);
  Domain out_grad_domain = runtime->get_index_space_domain(
    ctx, task->regions[0].region.get_index_space());
  Domain in0_domain = runtime->get_index_space_domain(
    ctx, task->regions[1].region.get_index_space());
  Domain in1_domain = runtime->get_index_space_domain(
    ctx, task->regions[2].region.get_index_space());
  Domain in0_grad_domain = runtime->get_index_space_domain(
    ctx, task->regions[3].region.get_index_space());
  Domain in1_grad_domain = runtime->get_index_space_domain(
    ctx, task->regions[4].region.get_index_space());
  assert(out_grad_domain == in0_domain);
  assert(out_grad_domain == in1_domain);
  assert(out_grad_domain == in0_grad_domain);
  assert(out_grad_domain == in1_grad_domain);

  const float* out_grad_ptr = helperGetTensorPointerR<float>(
    regions[0], task->regions[0], FID_DATA, ctx, runtime);
  const float* in1_ptr = helperGetTensorPointerR<float>(
    regions[1], task->regions[1], FID_DATA, ctx, runtime);
  const float* in2_ptr = helperGetTensorPointerR<float>(
    regions[2], task->regions[2], FID_DATA, ctx, runtime);
  float* in1_grad_ptr = helperGetTensorPointerWO<float>(
    regions[1], task->regions[1], FID_DATA, ctx, runtime);
  float* in2_grad_ptr = helperGetTensorPointerWO<float>(
    regions[2], task->regions[2], FID_DATA, ctx, runtime);

  elewise_binary_backward_kernel<<<GET_BLOCKS(out_grad_domain.get_volume()), CUDA_NUM_THREADS>>>(
    out_grad_domain.get_volume(), ele->op_type, out_grad_ptr, in1_ptr, in2_ptr,
    in1_grad_ptr, in2_grad_ptr);
}

void ElementBinary::backward(const FFModel& ff)
{
  ArgumentMap argmap;
  Context ctx = ff.config.lg_ctx;
  Runtime* runtime = ff.config.lg_hlr;
  IndexLauncher launcher(ELEMENTBINARY_BWD_TASK_ID, task_is,
                         TaskArgument(this, sizeof(Linear)), argmap,
                         Predicate::TRUE_PRED, false/*must*/, 0/*mapper_id*/,
                         FFConfig::get_hash_id(std::string(name)));
  // regions[0](I): output_grad
  launcher.add_region_requirement(
    RegionRequirement(output.part_grad, 0/*projection id*/,
                      READ_ONLY, EXCLUSIVE, output.region_grad));
  launcher.add_field(0, FID_DATA);
  // regions[1](I): input0
  launcher.add_region_requirement(
    RegionRequirement(input_lps[0], 0/*projection id*/,
                      READ_ONLY, EXCLUSIVE, inputs[0].region));
  launcher.add_field(1, FID_DATA);
  // regions[2](I): input1
  launcher.add_region_requirement(
    RegionRequirement(input_lps[1], 0/*projection id*/,
                      READ_ONLY, EXCLUSIVE, inputs[1].region));
  launcher.add_field(2, FID_DATA);
  // regions[3](O): input0_grad
  launcher.add_region_requirement(
    RegionRequirement(input_grad_lps[0], 0/*projection id*/,
                      WRITE_ONLY, EXCLUSIVE, inputs[0].region_grad));
  launcher.add_field(3, FID_DATA);
  // regions[4](O): input1_grad
  launcher.add_region_requirement(
    RegionRequirement(input_grad_lps[1], 0/*projection id*/,
                      WRITE_ONLY, EXCLUSIVE, inputs[1].region_grad));
  launcher.add_field(4, FID_DATA);
  runtime->execute_index_space(ctx, launcher);
}
